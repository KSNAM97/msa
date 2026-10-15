package com.example.ordersystem.member.controller;

import org.springframework.http.HttpStatus;
import org.springframework.http.ResponseEntity;
import org.springframework.jdbc.core.JdbcTemplate;
import org.springframework.web.bind.annotation.*;

import java.sql.ResultSet;
import java.sql.ResultSetMetaData;
import java.sql.Statement;
import java.util.*;

// 관리자 페이지의 "DB 보기" 기능 (1인 쇼핑몰: 운영자가 쇼핑몰 화면 안에서 바로 데이터를 확인한다).
// 모든 서비스가 같은 DB(ordermsa)를 쓰므로 member 서비스에서 전체 테이블을 조회한다.
//
// [안전 장치]
//  1) 관리자만: 게이트웨이가 JWT 에서 꺼내 넣는 X-User-Role 이 ROLE_ADMIN 일 때만 동작 (클라이언트가 위조할 수 없음)
//  2) 읽기 전용: 조회 쿼리(SELECT/SHOW/DESCRIBE/EXPLAIN)만 허용하고, 연결 자체도 읽기 전용으로 설정한다. 수정/삭제는 불가
//  3) 테이블 이름은 "실제 존재하는 테이블 목록"에 있는 것만 허용 (SQL 이 이름에 섞여 들어가는 것을 차단)
//  4) 비밀번호 컬럼은 값을 가려서(********) 보여준다
//  5) 결과는 최대 200행, 쿼리 실행 시간은 5초로 제한
// 데이터를 고치거나 지우려면 전용 관리 화면(상품 삭제, 주문 취소 등)이나 Adminer 를 사용한다.
@RestController
@RequestMapping("/member/admin/db")
public class AdminDbController {
    private static final int MAX_ROWS = 200;
    private final JdbcTemplate jdbc;

    public AdminDbController(JdbcTemplate jdbc) {
        this.jdbc = jdbc;
    }

    private static boolean notAdmin(String role) {
        return !"ROLE_ADMIN".equals(role);
    }

    // 현재 DB 의 테이블 목록과 행 수. 테이블 수가 적어서 정확한 행 수를 위해 COUNT(*) 를 쓴다
    @GetMapping("/tables")
    public ResponseEntity<?> tables(@RequestHeader(value = "X-User-Role", required = false) String role) {
        if (notAdmin(role)) return forbidden();
        List<Map<String, Object>> result = new ArrayList<>();
        for (String name : tableNames()) {
            Long count = jdbc.queryForObject("SELECT COUNT(*) FROM `" + name + "`", Long.class);
            result.add(Map.of("name", name, "rows", count == null ? 0 : count));
        }
        return new ResponseEntity<>(result, HttpStatus.OK);
    }

    // 테이블 내용(최신순, 페이지 단위). 이름은 반드시 존재하는 테이블 목록에서 확인한 뒤 사용한다
    @GetMapping("/tables/{name}")
    public ResponseEntity<?> rows(@PathVariable String name,
                                  @RequestParam(defaultValue = "0") int page,
                                  @RequestParam(defaultValue = "20") int size,
                                  @RequestHeader(value = "X-User-Role", required = false) String role) {
        if (notAdmin(role)) return forbidden();
        if (!tableNames().contains(name)) {
            return new ResponseEntity<>("없는 테이블입니다.", HttpStatus.NOT_FOUND);
        }
        int safeSize = Math.min(Math.max(size, 1), 100);
        int offset = Math.max(page, 0) * safeSize;
        // 첫 번째 컬럼(보통 id) 내림차순 = 최신순
        return new ResponseEntity<>(
                run("SELECT * FROM `" + name + "` ORDER BY 1 DESC LIMIT " + safeSize + " OFFSET " + offset, safeSize),
                HttpStatus.OK);
    }

    // 직접 조회 쿼리 실행 (읽기 전용)
    @PostMapping("/query")
    public ResponseEntity<?> query(@RequestBody Map<String, String> body,
                                   @RequestHeader(value = "X-User-Role", required = false) String role) {
        if (notAdmin(role)) return forbidden();
        String sql = body.getOrDefault("sql", "").trim();
        if (sql.endsWith(";")) sql = sql.substring(0, sql.length() - 1).trim();   // 끝의 세미콜론 1개는 허용
        String lower = sql.toLowerCase(Locale.ROOT);
        boolean readOnlyStart = lower.startsWith("select ") || lower.startsWith("show ")
                || lower.startsWith("describe ") || lower.startsWith("desc ") || lower.startsWith("explain ");
        // 한 번에 한 문장만(;), 파일 쓰기/지연 공격 함수 차단
        boolean dangerous = lower.contains(";") || lower.contains("into outfile") || lower.contains("into dumpfile")
                || lower.contains("load_file") || lower.contains("sleep(") || lower.contains("benchmark(");
        if (sql.isEmpty() || !readOnlyStart || dangerous) {
            return new ResponseEntity<>("SELECT / SHOW / DESCRIBE / EXPLAIN 한 문장만 실행할 수 있습니다.", HttpStatus.BAD_REQUEST);
        }
        try {
            return new ResponseEntity<>(run(sql, MAX_ROWS), HttpStatus.OK);
        } catch (Exception e) {
            // DB 오류 메시지(문법 오류 등)를 그대로 돌려줘서 쿼리를 고칠 수 있게 한다
            String msg = e.getCause() != null ? e.getCause().getMessage() : e.getMessage();
            return new ResponseEntity<>(msg, HttpStatus.BAD_REQUEST);
        }
    }

    // ---------- 내부 구현 ----------

    private Set<String> tableNames() {
        return new LinkedHashSet<>(jdbc.queryForList(
                "SELECT TABLE_NAME FROM information_schema.TABLES WHERE TABLE_SCHEMA = DATABASE() AND TABLE_TYPE = 'BASE TABLE' ORDER BY TABLE_NAME",
                String.class));
    }

    // 읽기 전용 연결로 실행하고 {columns, rows, truncated} 로 변환한다.
    // 풀링된 연결을 쓰므로 끝나면 반드시 readOnly 를 원래대로 돌려놓는다
    private Map<String, Object> run(String sql, int maxRows) {
        return jdbc.execute((java.sql.Connection con) -> {
            boolean original = con.isReadOnly();
            con.setReadOnly(true);
            try (Statement st = con.createStatement()) {
                st.setMaxRows(maxRows + 1);     // 한 행 더 읽어 "잘렸는지" 판단
                st.setQueryTimeout(5);
                try (ResultSet rs = st.executeQuery(sql)) {
                    ResultSetMetaData md = rs.getMetaData();
                    int n = md.getColumnCount();
                    List<String> columns = new ArrayList<>();
                    boolean[] mask = new boolean[n];
                    for (int i = 1; i <= n; i++) {
                        String label = md.getColumnLabel(i);
                        columns.add(label);
                        mask[i - 1] = "password".equalsIgnoreCase(label);   // 비밀번호(해시)는 가린다
                    }
                    List<List<Object>> rows = new ArrayList<>();
                    boolean truncated = false;
                    while (rs.next()) {
                        if (rows.size() >= maxRows) { truncated = true; break; }
                        List<Object> row = new ArrayList<>();
                        for (int i = 1; i <= n; i++) {
                            Object v = rs.getObject(i);
                            if (mask[i - 1] && v != null) v = "********";
                            else if (v instanceof byte[]) v = "(binary)";
                            else if (v != null && !(v instanceof Number) && !(v instanceof Boolean)) v = v.toString();
                            row.add(v);
                        }
                        rows.add(row);
                    }
                    Map<String, Object> result = new LinkedHashMap<>();
                    result.put("columns", columns);
                    result.put("rows", rows);
                    result.put("truncated", truncated);
                    return result;
                }
            } finally {
                con.setReadOnly(original);
            }
        });
    }

    private static ResponseEntity<?> forbidden() {
        return new ResponseEntity<>("관리자만 사용할 수 있습니다.", HttpStatus.FORBIDDEN);
    }
}

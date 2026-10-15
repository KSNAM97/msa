package com.example.ordersystem.member.controller;

import com.fasterxml.jackson.databind.JsonNode;
import com.fasterxml.jackson.databind.ObjectMapper;
import org.springframework.beans.factory.annotation.Value;
import org.springframework.http.HttpStatus;
import org.springframework.http.ResponseEntity;
import org.springframework.web.bind.annotation.*;

import java.net.URI;
import java.net.URLEncoder;
import java.net.http.HttpClient;
import java.net.http.HttpRequest;
import java.net.http.HttpResponse;
import java.nio.charset.StandardCharsets;
import java.time.Duration;
import java.util.*;

// 관리자 페이지의 "EKS / ArgoCD / 서비스" 현황용 지표 조회 창구.
// 브라우저가 Prometheus 에 직접 접근할 수 없으므로(내부 주소 + 인증 없음) 서버가 대신 조회해서 필요한 값만 돌려준다.
//
// [안전 장치]
//  1) 관리자만: X-User-Role(ROLE_ADMIN) 확인 - 게이트웨이가 JWT 에서 넣는 값이라 위조 불가
//  2) 임의 PromQL 실행 불가: 아래 이름표(name)에 미리 정해 둔 조회만 가능 (사용자가 쿼리 문자열을 보낼 수 없음)
//  3) 짧은 타임아웃(3초): Prometheus 가 느려도 관리자 페이지가 멈추지 않게 한다
@RestController
@RequestMapping("/member/admin/metrics")
public class AdminMetricsController {

    // 이름 -> PromQL. 화면에서는 이름만 보낸다
    private static final Map<String, String> QUERIES = Map.ofEntries(
            Map.entry("nodes_up", "count(up{job=\"node-exporter\"} == 1)"),
            Map.entry("node_cpu", "100 - (avg by (instance) (rate(node_cpu_seconds_total{mode=\"idle\"}[2m])) * 100)"),
            Map.entry("node_mem", "(1 - node_memory_MemAvailable_bytes / node_memory_MemTotal_bytes) * 100"),
            Map.entry("pod_cpu", "sum by (pod) (rate(container_cpu_usage_seconds_total{namespace=\"ksnam97\",container!=\"\",container!=\"POD\"}[2m]))"),
            Map.entry("pod_mem", "sum by (pod) (container_memory_working_set_bytes{namespace=\"ksnam97\",container!=\"\",container!=\"POD\"})"),
            Map.entry("services_up", "up{job=\"spring-services\"}"),
            Map.entry("req_rate", "sum by (app) (rate(http_server_requests_seconds_count[1m]))"),
            Map.entry("err_rate", "sum by (app) (rate(http_server_requests_seconds_count{status=~\"5..\"}[1m]))"),
            // ArgoCD 애플리케이션 컨트롤러가 내보내는 앱별 동기화/상태 정보 (Prometheus 의 argocd 수집 설정 필요)
            Map.entry("argocd_apps", "argocd_app_info")
    );

    private final ObjectMapper mapper = new ObjectMapper();
    private final HttpClient http = HttpClient.newBuilder().connectTimeout(Duration.ofSeconds(2)).build();
    private final String prometheusUrl;

    public AdminMetricsController(@Value("${PROMETHEUS_URL:http://prometheus-service.monitoring.svc.cluster.local:9090}") String prometheusUrl) {
        this.prometheusUrl = prometheusUrl;
    }

    @GetMapping("/{name}")
    public ResponseEntity<?> metric(@PathVariable String name,
                                    @RequestHeader(value = "X-User-Role", required = false) String role) {
        if (!"ROLE_ADMIN".equals(role)) {
            return new ResponseEntity<>("관리자만 사용할 수 있습니다.", HttpStatus.FORBIDDEN);
        }
        String promql = QUERIES.get(name);
        if (promql == null) {
            return new ResponseEntity<>("지원하지 않는 지표입니다.", HttpStatus.NOT_FOUND);
        }
        try {
            HttpRequest req = HttpRequest.newBuilder(URI.create(prometheusUrl + "/api/v1/query?query=" + URLEncoder.encode(promql, StandardCharsets.UTF_8)))
                    .timeout(Duration.ofSeconds(3)).GET().build();
            HttpResponse<String> res = http.send(req, HttpResponse.BodyHandlers.ofString());
            JsonNode result = mapper.readTree(res.body()).path("data").path("result");
            // Prometheus 응답 -> [{labels:{...}, value:숫자}] 로 단순화 (화면이 다루기 쉽게)
            List<Map<String, Object>> out = new ArrayList<>();
            for (JsonNode item : result) {
                Map<String, Object> row = new LinkedHashMap<>();
                row.put("labels", mapper.convertValue(item.path("metric"), Map.class));
                row.put("value", item.path("value").path(1).asText());
                out.add(row);
            }
            return new ResponseEntity<>(out, HttpStatus.OK);
        } catch (Exception e) {
            // Prometheus 가 없거나 느릴 때: 화면이 "지표를 가져오지 못함"으로 표시하도록 503 을 돌려준다
            return new ResponseEntity<>("지표를 가져오지 못했습니다.", HttpStatus.SERVICE_UNAVAILABLE);
        }
    }
}

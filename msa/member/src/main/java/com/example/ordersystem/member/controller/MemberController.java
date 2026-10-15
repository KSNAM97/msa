package com.example.ordersystem.member.controller;

import com.example.ordersystem.member.service.JwtTokenProvider;
import com.example.ordersystem.member.domain.Member;
import com.example.ordersystem.member.dto.LoginDto;
import com.example.ordersystem.member.dto.MemberRefreshDto;
import com.example.ordersystem.member.dto.MemberSaveReqDto;
import com.example.ordersystem.member.service.MemberService;
import io.jsonwebtoken.Claims;
import io.jsonwebtoken.Jwts;
import org.springframework.beans.factory.annotation.Value;
import org.springframework.http.HttpStatus;
import org.springframework.http.ResponseEntity;
import org.springframework.web.bind.annotation.*;

import java.util.HashMap;
import java.util.Map;

@RestController
@RequestMapping("/member")
public class MemberController {
    private final MemberService memberService;
    private final JwtTokenProvider jwtTokenProvider;

    @Value("${jwt.secretKeyRt}")
    private String secretKeyRt;

    public MemberController(MemberService memberService, JwtTokenProvider jwtTokenProvider) {
        this.memberService = memberService;
        this.jwtTokenProvider = jwtTokenProvider;
    }

    @PostMapping("/create")
    public ResponseEntity<?> memberCreate(@RequestBody MemberSaveReqDto memberSaveReqDto){
        Long memberId = memberService.save(memberSaveReqDto);

        Map<String, Object> response = new HashMap<>();
        response.put("id", memberId);
        response.put("message", "회원가입이 완료되었습니다.");
        return new ResponseEntity<>(response, HttpStatus.CREATED);
    }

    // 관리자: 회원 목록 조회. X-User-Role 은 게이트웨이가 JWT 의 role 로 넣어 주는 값이라 클라이언트가 위조할 수 없다
    @GetMapping("/list")
    public ResponseEntity<?> memberList(@RequestHeader(value = "X-User-Role", required = false) String role){
        if (!"ROLE_ADMIN".equals(role)) {
            return new ResponseEntity<>("관리자만 조회할 수 있습니다.", HttpStatus.FORBIDDEN);
        }
        return new ResponseEntity<>(memberService.findAllMembers(), HttpStatus.OK);
    }

    // 내 정보 조회 / 수정 / 비밀번호 변경. 모두 게이트웨이가 JWT 에서 꺼낸 X-User-Id(= 내 계정)만 대상으로 한다 (다른 사람 계정은 건드릴 수 없음)
    @GetMapping("/me")
    public ResponseEntity<?> me(@RequestHeader("X-User-Id") String userId){
        return new ResponseEntity<>(memberService.findMe(Long.parseLong(userId)), HttpStatus.OK);
    }

    @PutMapping("/me")
    public ResponseEntity<?> updateMe(@RequestHeader("X-User-Id") String userId,
                                      @RequestBody com.example.ordersystem.member.dto.ProfileUpdateDto dto){
        return new ResponseEntity<>(memberService.updateProfile(Long.parseLong(userId), dto), HttpStatus.OK);
    }

    @PutMapping("/password")
    public ResponseEntity<?> changePassword(@RequestHeader("X-User-Id") String userId,
                                            @RequestBody com.example.ordersystem.member.dto.PasswordChangeDto dto){
        memberService.changePassword(Long.parseLong(userId), dto);
        return new ResponseEntity<>("비밀번호가 변경되었습니다.", HttpStatus.OK);
    }

    // 회원탈퇴 (본인). 게이트웨이가 JWT 에서 꺼낸 X-User-Id 로 "내 계정"만 대상으로 하고, 현재 비밀번호로 한 번 더 확인한다
    @PostMapping("/withdraw")
    public ResponseEntity<?> withdraw(@RequestHeader("X-User-Id") String userId,
                                      @RequestBody com.example.ordersystem.member.dto.WithdrawDto dto){
        memberService.withdraw(Long.parseLong(userId), dto.getPassword());
        return new ResponseEntity<>("탈퇴가 완료되었습니다.", HttpStatus.OK);
    }

    @PostMapping("/doLogin")
    public ResponseEntity<?> doLogin(@RequestBody LoginDto dto){
        Member member = memberService.login(dto);
        String token = jwtTokenProvider.createToken(member.getId().toString(), member.getRole().toString());
        String refreshToken = jwtTokenProvider.createRefreshToken(member.getLoginId(), member.getRole().toString());

        Map<String, Object> loginInfo = new HashMap<>();
        loginInfo.put("id", member.getId());
        loginInfo.put("name", member.getName());
        loginInfo.put("nickname", member.getNickname());
        loginInfo.put("loginId", member.getLoginId());
        loginInfo.put("email", member.getEmail());
        loginInfo.put("role", member.getRole());
        loginInfo.put("token", token);
        loginInfo.put("refreshToken", refreshToken);
        loginInfo.put("message", "로그인에 성공했습니다.");
        return new ResponseEntity<>(loginInfo, HttpStatus.OK);
    }

    @PostMapping("/refresh-token")
    public ResponseEntity<?> generateNewAt(@RequestBody MemberRefreshDto dto){
        try {
            Claims claims = Jwts.parserBuilder()
                    .setSigningKey(secretKeyRt)
                    .build()
                    .parseClaimsJws(dto.getRefreshToken())
                    .getBody();

            String loginId = claims.getSubject();
            Member member = memberService.findByLoginId(loginId);
            String role = claims.get("role", String.class);
            String newAccessToken = jwtTokenProvider.createToken(member.getId().toString(), role);

            Map<String, Object> tokenMap = new HashMap<>();
            tokenMap.put("token", newAccessToken);
            return new ResponseEntity<>(tokenMap, HttpStatus.OK);
        } catch (Exception e) {
            return new ResponseEntity<>("refresh token 검증 실패", HttpStatus.BAD_REQUEST);
        }
    }
}

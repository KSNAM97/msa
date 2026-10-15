package com.example.ordersystem.member.service;

import com.example.ordersystem.member.domain.Member;
import com.example.ordersystem.member.domain.Role;
import com.example.ordersystem.member.repository.MemberRepository;
import org.springframework.boot.CommandLineRunner;
import org.springframework.security.crypto.password.PasswordEncoder;
import org.springframework.stereotype.Component;

@Component
public class InitialDataLoader implements CommandLineRunner {
    private final MemberRepository memberRepository;
    private final PasswordEncoder passwordEncoder;

    public InitialDataLoader(MemberRepository memberRepository, PasswordEncoder passwordEncoder) {
        this.memberRepository = memberRepository;
        this.passwordEncoder = passwordEncoder;
    }

    @Override
    public void run(String... args) {
        if(memberRepository.findByLoginId("admin").isPresent() || memberRepository.findByEmail("admin@naver.com").isPresent()) {
            return;
        }

        // 초기 관리자 비밀번호는 소스에 두지 않고 환경변수(ADMIN_INITIAL_PASSWORD)로 받는다.
        // 값이 없으면 관리자 계정을 만들지 않는다 (공개 저장소에 기본 비밀번호가 남지 않도록)
        String adminPassword = System.getenv("ADMIN_INITIAL_PASSWORD");
        if (adminPassword == null || adminPassword.isBlank()) {
            System.out.println("ADMIN_INITIAL_PASSWORD 가 없어 초기 관리자 계정을 만들지 않습니다.");
            return;
        }

        Member member = Member.builder()
                .name("관리자")
                .loginId("admin")
                .nickname("관리자")
                .email("admin@naver.com")
                .password(passwordEncoder.encode(adminPassword))
                .role(Role.ADMIN)
                .build();
        memberRepository.save(member);
    }
}

package com.example.ordersystem.member.dto;

import com.example.ordersystem.member.domain.Member;
import lombok.AllArgsConstructor;
import lombok.Builder;
import lombok.Data;
import lombok.NoArgsConstructor;

import java.time.LocalDateTime;

// 관리자 회원 목록 응답. 비밀번호(해시 포함)는 절대 내려주지 않는다
@Data
@Builder
@NoArgsConstructor
@AllArgsConstructor
public class MemberResDto {
    private Long id;
    private String name;
    private String loginId;
    private String nickname;
    private String email;
    private String role;
    private LocalDateTime createdTime;

    public static MemberResDto from(Member m) {
        return MemberResDto.builder()
                .id(m.getId()).name(m.getName()).loginId(m.getLoginId()).nickname(m.getNickname())
                .email(m.getEmail()).role(m.getRole().name()).createdTime(m.getCreatedTime())
                .build();
    }
}

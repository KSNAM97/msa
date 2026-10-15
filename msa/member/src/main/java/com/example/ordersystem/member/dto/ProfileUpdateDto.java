package com.example.ordersystem.member.dto;

import lombok.AllArgsConstructor;
import lombok.Data;
import lombok.NoArgsConstructor;

// 내 정보 수정 요청. 아이디(loginId)와 권한(role)은 바꿀 수 없다 (이 DTO 에 없으므로 요청에 넣어도 무시됨)
@NoArgsConstructor
@AllArgsConstructor
@Data
public class ProfileUpdateDto {
    private String name;
    private String nickname;
    private String email;
}

package com.example.ordersystem.member.dto;

import lombok.AllArgsConstructor;
import lombok.Data;
import lombok.NoArgsConstructor;

// 회원탈퇴 요청: 본인 확인을 위해 현재 비밀번호를 한 번 더 받는다 (로그인 토큰이 탈취돼도 함부로 탈퇴되지 않게)
@NoArgsConstructor
@AllArgsConstructor
@Data
public class WithdrawDto {
    private String password;
}

package com.example.ordersystem.member.dto;

import lombok.AllArgsConstructor;
import lombok.Data;
import lombok.NoArgsConstructor;

// 비밀번호 변경 요청: 현재 비밀번호를 확인한 뒤 새 비밀번호로 바꾼다
@NoArgsConstructor
@AllArgsConstructor
@Data
public class PasswordChangeDto {
    private String currentPassword;
    private String newPassword;
}

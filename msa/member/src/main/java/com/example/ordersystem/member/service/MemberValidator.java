package com.example.ordersystem.member.service;

import java.util.regex.Pattern;

// 회원 입력값 최소 조건 검사 (가입 / 정보 수정 / 비밀번호 변경에서 공통 사용).
// 화면(HTML)에서도 같은 조건을 안내하지만, 화면 검사는 우회할 수 있으므로 서버에서 반드시 다시 검사한다.
// 조건을 바꾸면 frontend 의 signup.html / mypage.html 안내 문구와 pattern 도 함께 바꿀 것.
public final class MemberValidator {
    private MemberValidator() {}

    // 이메일: 공백 없이 "아이디@도메인.최상위도메인" 형태, 100자 이하
    private static final Pattern EMAIL = Pattern.compile("^[A-Za-z0-9._%+-]+@[A-Za-z0-9-]+(\\.[A-Za-z0-9-]+)*\\.[A-Za-z]{2,}$");
    // 비밀번호: 8~64자, 영문과 숫자를 각각 1개 이상 포함 (공백 불가)
    private static final Pattern PASSWORD = Pattern.compile("^(?=.*[A-Za-z])(?=.*\\d)\\S{8,64}$");

    public static void email(String email) {
        if (email == null || email.length() > 100 || !EMAIL.matcher(email).matches()) {
            throw new IllegalArgumentException("이메일 형식이 올바르지 않습니다. (예: name@example.com, 100자 이하)");
        }
    }

    public static void password(String password) {
        if (password == null || !PASSWORD.matcher(password).matches()) {
            throw new IllegalArgumentException("비밀번호는 8~64자이며 영문과 숫자를 모두 포함해야 합니다. (공백 불가)");
        }
    }

    // 이름/닉네임: 공백만 있으면 안 되고 30자 이하
    public static void text(String label, String value) {
        if (value == null || value.isBlank() || value.trim().length() > 30) {
            throw new IllegalArgumentException(label + "은(는) 1~30자로 입력해주세요.");
        }
    }
}

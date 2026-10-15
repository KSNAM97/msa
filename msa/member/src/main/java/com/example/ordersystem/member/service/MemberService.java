package com.example.ordersystem.member.service;

import com.example.ordersystem.member.domain.Member;
import com.example.ordersystem.member.dto.LoginDto;
import com.example.ordersystem.member.dto.MemberSaveReqDto;
import com.example.ordersystem.member.repository.MemberRepository;
import org.springframework.security.crypto.password.PasswordEncoder;
import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Transactional;

@Service
@Transactional
public class MemberService {
    private final MemberRepository memberRepository;
    private final PasswordEncoder passwordEncoder;

    public MemberService(MemberRepository memberRepository, PasswordEncoder passwordEncoder) {
        this.memberRepository = memberRepository;
        this.passwordEncoder = passwordEncoder;
    }

    public Long save(MemberSaveReqDto memberSaveReqDto){
        // 입력값 최소 조건 (이메일 형식, 비밀번호 규칙, 이름/닉네임 길이) - 서버에서 반드시 검사
        MemberValidator.email(memberSaveReqDto.getEmail());
        MemberValidator.password(memberSaveReqDto.getPassword());
        MemberValidator.text("이름", memberSaveReqDto.getName());
        MemberValidator.text("닉네임", memberSaveReqDto.getNickname());

        if(memberRepository.findByLoginId(memberSaveReqDto.getLoginId()).isPresent()){
            throw new IllegalArgumentException("이미 존재하는 아이디입니다.");
        }

        if(memberRepository.findByEmail(memberSaveReqDto.getEmail()).isPresent()){
            throw new IllegalArgumentException("이미 존재하는 이메일입니다.");
        }

        String password = passwordEncoder.encode(memberSaveReqDto.getPassword());
        Member member = memberRepository.save(memberSaveReqDto.toEntity(password));
        return member.getId();
    }

    public Member findByLoginId(String loginId){
        return memberRepository.findByLoginId(loginId)
                .orElseThrow(() -> new IllegalArgumentException("존재하지 않는 회원입니다."));
    }

    public Member login(LoginDto dto){
        Member member = memberRepository.findByLoginId(dto.getLoginId())
                .orElseThrow(() -> new IllegalArgumentException("아이디 또는 비밀번호가 일치하지 않습니다."));

        if(!passwordEncoder.matches(dto.getPassword(), member.getPassword())){
            throw new IllegalArgumentException("아이디 또는 비밀번호가 일치하지 않습니다.");
        }

        return member;
    }

    // 내 정보 조회 (비밀번호 제외 DTO)
    @Transactional(readOnly = true)
    public com.example.ordersystem.member.dto.MemberResDto findMe(Long memberId){
        return com.example.ordersystem.member.dto.MemberResDto.from(memberRepository.findById(memberId)
                .orElseThrow(() -> new IllegalArgumentException("존재하지 않는 회원입니다.")));
    }

    // 내 정보 수정: 이름/닉네임/이메일. 이메일은 형식 검사 + 다른 회원과 중복 불가
    public com.example.ordersystem.member.dto.MemberResDto updateProfile(Long memberId, com.example.ordersystem.member.dto.ProfileUpdateDto dto){
        MemberValidator.text("이름", dto.getName());
        MemberValidator.text("닉네임", dto.getNickname());
        MemberValidator.email(dto.getEmail());
        Member member = memberRepository.findById(memberId)
                .orElseThrow(() -> new IllegalArgumentException("존재하지 않는 회원입니다."));
        // 본인이 이미 쓰는 이메일이면 통과, 다른 회원이 쓰는 이메일이면 거절
        memberRepository.findByEmail(dto.getEmail())
                .filter(other -> !other.getId().equals(memberId))
                .ifPresent(other -> { throw new IllegalArgumentException("이미 사용 중인 이메일입니다."); });
        member.updateProfile(dto.getName().trim(), dto.getNickname().trim(), dto.getEmail());
        return com.example.ordersystem.member.dto.MemberResDto.from(member);
    }

    // 비밀번호 변경: 현재 비밀번호 확인 -> 새 비밀번호 규칙 검사 -> 현재와 다른 값인지 확인 -> 암호화해서 저장
    public void changePassword(Long memberId, com.example.ordersystem.member.dto.PasswordChangeDto dto){
        Member member = memberRepository.findById(memberId)
                .orElseThrow(() -> new IllegalArgumentException("존재하지 않는 회원입니다."));
        if (dto.getCurrentPassword() == null || !passwordEncoder.matches(dto.getCurrentPassword(), member.getPassword())) {
            throw new IllegalArgumentException("현재 비밀번호가 일치하지 않습니다.");
        }
        MemberValidator.password(dto.getNewPassword());
        if (dto.getNewPassword().equals(dto.getCurrentPassword())) {
            throw new IllegalArgumentException("새 비밀번호는 현재 비밀번호와 달라야 합니다.");
        }
        member.changePassword(passwordEncoder.encode(dto.getNewPassword()));
    }

    // 회원탈퇴: 본인 비밀번호를 확인한 뒤 회원 정보를 삭제한다.
    // - 관리자 계정은 탈퇴할 수 없다(관리자가 없어지면 상품/주문 관리가 불가능해지므로)
    // - 주문 내역은 서비스 기록으로 남긴다(ordering 서비스의 주문은 지우지 않음). 장바구니는 화면이 탈퇴 전에 비운다.
    public void withdraw(Long memberId, String password){
        Member member = memberRepository.findById(memberId)
                .orElseThrow(() -> new IllegalArgumentException("존재하지 않는 회원입니다."));
        if (member.getRole() == com.example.ordersystem.member.domain.Role.ADMIN) {
            throw new IllegalArgumentException("관리자 계정은 탈퇴할 수 없습니다.");
        }
        if (password == null || !passwordEncoder.matches(password, member.getPassword())) {
            throw new IllegalArgumentException("비밀번호가 일치하지 않습니다.");
        }
        memberRepository.delete(member);
    }

    // 관리자용 회원 목록(최신 가입순). 비밀번호가 없는 DTO 로 변환해서 반환한다
    @Transactional(readOnly = true)
    public java.util.List<com.example.ordersystem.member.dto.MemberResDto> findAllMembers(){
        return memberRepository.findAll(org.springframework.data.domain.Sort.by(org.springframework.data.domain.Sort.Direction.DESC, "id"))
                .stream().map(com.example.ordersystem.member.dto.MemberResDto::from).toList();
    }
}

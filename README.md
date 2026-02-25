# kmsg

> **Disclaimer**
>
> `kmsg`는 Kakao Corp. 의 공식 도구가 아닙니다.
> 사용자는 본인 계정/환경에서 관련 법규, 서비스 약관, 회사 보안 정책을 준수할 책임이 있습니다.
> 이 도구 사용으로 발생할 수 있는 계정 제한, 오작동, 데이터 손실, 기타 손해에 대한 책임은 사용자에게 있습니다.

macOS에서 카카오톡 메시지를 CLI로 보내는 도구입니다.

## 빠른 시작

요구사항:

- macOS 13+
- [macOS용 KakaoTalk](https://apps.apple.com/kr/app/kakaotalk/id869223134?mt=12) 설치

### 1) 한 줄 설치 (curl)

```bash
mkdir -p ~/.local/bin && curl -fL https://github.com/channprj/kmsg/releases/latest/download/kmsg-macos-universal -o ~/.local/bin/kmsg && chmod +x ~/.local/bin/kmsg
```

### 2) 설치 확인

```bash
~/.local/bin/kmsg status
```

권한 팝업이 뜨면 허용해 주세요.

### 3) PATH 등록 (선택)

`kmsg`를 바로 실행하고 싶다면:

```bash
echo 'export PATH="$HOME/.local/bin:$PATH"' >> ~/.zshrc && source ~/.zshrc
```

## 가장 많이 쓰는 명령

```bash
kmsg status
kmsg send "본인, 친구, 또는 단톡방 이름" "안녕하세요"
kmsg send "본인, 친구, 또는 단톡방 이름" "$(date '+%Y-%m-%d %H:%M:%S') 테스트" --close-after-send
kmsg chats
kmsg read "본인, 친구, 또는 단톡방 이름" --limit 30
```

## 권한 문제 해결

`kmsg`는 손쉬운 사용(Accessibility) 권한이 필요합니다.

앱이 자동 요청에 실패하면:

1. 시스템 설정 열기
2. `개인정보 보호 및 보안 > 손쉬운 사용`
3. `kmsg` 토글 켜기

## 고급 옵션

```bash
kmsg send "본인, 친구, 또는 단톡방 이름" "테스트" --trace-ax
KMSG_AX_TIMEOUT=0.25 kmsg send "본인, 친구, 또는 단톡방 이름" "테스트"
kmsg cache warmup --recipient "본인, 친구, 또는 단톡방 이름" --trace-ax
```

## 소스에서 빌드 (개발자용)

```bash
git clone https://github.com/channprj/kmsg.git
cd kmsg
swift build -c release
install -m 755 .build/release/kmsg ~/.local/bin/kmsg
```

## 릴리스 배포 (메인테이너)

`v*` 태그를 푸시하면 GitHub Actions가 자동으로 빌드해서
`kmsg-macos-universal` 파일을 Releases에 업로드합니다.

```bash
# gh 토큰이 만료됐으면 재로그인
gh auth login -h github.com

# 릴리스 태그 생성/푸시
git tag v0.1.0
git push origin v0.1.0
```

필요하면 Actions를 수동 실행할 수 있습니다.

```bash
gh workflow run release.yml -f tag=v0.1.0
```

## 참고

- 릴리스 설치는 최신 릴리스 자산 `kmsg-macos-universal`을 사용합니다.
- 다운로드 실패 시: https://github.com/channprj/kmsg/releases 에서 직접 내려받아 `~/.local/bin/kmsg`로 저장 후 `chmod +x ~/.local/bin/kmsg`.

## Inspiration

This project is strongly inspired by:

- [imsg](https://github.com/steipete/imsg)
- [openclaw](https://github.com/openclaw/openclaw)

## 라이선스

MIT - [LICENSE](LICENSE)

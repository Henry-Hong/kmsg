# kmsg

> **Disclaimer**: `kmsg`는 Kakao Corp. 의 공식 도구가 아닙니다.
> 사용자는 본인 계정/환경에서 관련 법규, 서비스 약관, 회사 보안 정책을 준수할 책임이 있습니다.
> 이 도구 사용으로 발생할 수 있는 계정 제한, 오작동, 데이터 손실, 기타 손해에 대한 책임은 사용자에게 있습니다.

`kmsg` 는 macOS에서 카카오톡 메시지를 CLI 로 읽고 보내는 도구입니다. 단순한 수동 CLI 를 넘어, AI Agent 또는 Hook 이벤트 등의 자동화 파이프라인에 연결하기 쉽도록 구현했습니다.

## Demo

https://github.com/user-attachments/assets/c620b2e3-7106-40fa-86d1-ed847e3b1a6f

## 빠른 시작

요구사항:

- macOS 13+
- [macOS용 KakaoTalk](https://apps.apple.com/kr/app/kakaotalk/id869223134?mt=12) 설치

### 설치

```bash
mkdir -p ~/.local/bin && curl -fL https://github.com/channprj/kmsg/releases/latest/download/kmsg-macos-universal -o ~/.local/bin/kmsg && chmod +x ~/.local/bin/kmsg
```

설치 확인은 아래와 같이 진행합니다.

```bash
~/.local/bin/kmsg status
```

권한 팝업이 뜨면 허용해 주세요.

`kmsg`를 바로 실행하고 싶다면 아래와 같이 PATH 등록을 해주세요.

```bash
echo 'export PATH="$HOME/.local/bin:$PATH"' >> ~/.zshrc && source ~/.zshrc
```

## 가장 많이 쓰는 명령

```bash
kmsg status
kmsg send "본인, 친구, 또는 단톡방 이름" "안녕하세요"
kmsg send "본인, 친구, 또는 단톡방 이름" "$(date '+%Y-%m-%d %H:%M:%S') 테스트"
kmsg send "본인, 친구, 또는 단톡방 이름" "테스트" --keep-window
kmsg chats
kmsg read "본인, 친구, 또는 단톡방 이름" --limit 20
kmsg read "본인, 친구, 또는 단톡방 이름" --limit 20 --keep-window
kmsg read "본인, 친구, 또는 단톡방 이름" --limit 20 --json
kmsg read "본인, 친구, 또는 단톡방 이름" --limit 20 --deep-recovery
```

## 권한 문제 해결

`kmsg`는 손쉬운 사용(Accessibility) 권한이 필요합니다.

앱이 자동 요청에 실패하면:

1. 시스템 설정 열기
2. `개인정보 보호 및 보안 > 손쉬운 사용`
3. `kmsg` 토글 켜기

## JSON 출력

`read` 명령은 `--json` 플래그로 구조화된 결과를 반환할 수 있습니다.

```bash
kmsg read "본인, 친구, 또는 단톡방 이름" --limit 20 --json
```

### 출력 형식

```json
{
  "chat": "홍길동",
  "fetched_at": "2026-02-26T01:23:45.678Z",
  "count": 20,
  "messages": [
    {
      "author": "홍길동",
      "time_raw": "00:27",
      "body": "밤이 깊었네"
    }
  ]
}
```

### 필드 설명

- `chat`: 실제로 읽은 채팅방 제목
- `fetched_at`: 메시지 수집 시각(ISO-8601 UTC)
- `count`: 반환된 메시지 개수
- `messages[].author`: 작성자 이름(추론 불가 시 `null`)
- `messages[].time_raw`: UI에서 읽힌 시각 문자열(없으면 `null`)
- `messages[].body`: 메시지 본문

### 주의

- `--json` 사용 시 JSON은 `stdout`으로만 출력됩니다.
- `--trace-ax` 로그는 `stderr`로 분리되므로 OpenClaw 같은 파이프 연동에서 안전하게 사용할 수 있습니다.

## MCP 연동

`kmsg` 는 MCP 로 붙여서 사용할 수도 있습니다.

우선, 아래와 같이 MCP 서버를 실행합니다.

```bash
python tools/kmsg-mcp.py
```

### OpenClaw 설정 예시

MCP 서버를 띄웠다면 아래와 같이 JSON 설정값을 주면서 MCP 연동을 해달라고 하면 됩니다. 정말 간단하죠? 그래도 args 의 path 는 수정하셔야 합니다.

```json
{
  "mcpServers": {
    "kmsg": {
      "command": "python3",
      "args": ["/path/to/kmsg/tools/kmsg-mcp.py"],
      "env": {
        "KMSG_BIN": "$HOME/.local/bin/kmsg",
        "KMSG_DEFAULT_DEEP_RECOVERY": "false",
        "KMSG_TRACE_DEFAULT": "false"
      }
    }
  }
}
```

### 제공되는 도구

- `kmsg_read`: `chat`, `limit`, `deep_recovery`, `keep_window`, `trace_ax`
- `kmsg_send`: `chat`, `message`, `confirm`, `deep_recovery`, `keep_window`, `trace_ax`

`kmsg_send`는 `confirm=true`일 때만 실제 전송을 수행합니다.

### MCP 빠른 사용

MCP 서버 연결 후, 아래 순서로 호출하면 됩니다.

1. 최근 메시지 읽기

```json
{
  "name": "kmsg_read",
  "arguments": {
    "chat": "홍길동",
    "limit": 20
  }
}
```

2. 사용자 확인 후 메시지 보내기 (`confirm=true`)

```json
{
  "name": "kmsg_send",
  "arguments": {
    "chat": "홍길동",
    "message": "확인 후 보냅니다.",
    "confirm": true
  }
}
```

openclaw 와의 자세한 연동/운영 가이드는 [docs/openclaw.md](./docs/openclaw.md) 를 참고하세요.
설정 템플릿은 [docs/openclaw.mcp.example.json](./docs/openclaw.mcp.example.json) 에도 포함되어 있습니다.

## 로컬 빌드 및 개발

```bash
git clone https://github.com/channprj/kmsg.git
cd kmsg
swift build -c release
install -m 755 .build/release/kmsg ~/.local/bin/kmsg
```

## Roadmap

진행 예정 항목은 [TODO.md](./TODO.md) 에서 관리합니다.

### 고급 옵션

```bash
kmsg send "본인, 친구, 또는 단톡방 이름" "테스트" --trace-ax
KMSG_AX_TIMEOUT=0.25 kmsg send "본인, 친구, 또는 단톡방 이름" "테스트"
kmsg cache warmup --recipient "본인, 친구, 또는 단톡방 이름" --trace-ax
kmsg cache warmup --recipient "본인, 친구, 또는 단톡방 이름" --keep-window
kmsg read "본인, 친구, 또는 단톡방 이름" --deep-recovery --trace-ax
kmsg send "본인, 친구, 또는 단톡방 이름" "테스트" --deep-recovery --trace-ax
```

`--deep-recovery`는 빠른 창 탐색이 실패할 때만 relaunch/open 복구를 추가로 수행합니다.
기본적으로 자동으로 연 카카오톡 창은 명령 종료 시 닫히며, `--keep-window`(또는 `-k`)로 유지할 수 있습니다.

### 디버깅 가이드 (inspect / trace-ax)

메시지 읽기/보내기가 기대와 다르면 아래 순서로 상태를 수집해 주세요.

```bash
# 1) 대상 채팅창 구조 확인
kmsg inspect --window 0 --depth 20

# 2) 읽기 경로/AX 로그 확인
kmsg read "본인, 친구, 또는 단톡방 이름" --limit 20 --trace-ax

# 3) 보내기 경로/AX 로그 확인
kmsg send "본인, 친구, 또는 단톡방 이름" "테스트" --trace-ax --dry-run
```

#### 팁

- `AXTextArea, value: "..."` 는 실제 메시지 본문 후보입니다.
- `AXStaticText, value: "5\n00:27"` 같은 값은 보통 카운트/시간 메타 정보입니다.
- 이슈 보고 시 `inspect` 출력과 `--trace-ax` 출력을 함께 첨부하면 원인 파악이 빨라집니다.

### Coding Agent에게 요청하기

개발을 진행하거나 버그 수정을 원할 때 Coding Agent에게 아래 정보와 함께 요청하면 좋습니다.

1. 실행한 명령어: `kmsg read ... --trace-ax`, `kmsg inspect ...`
2. 기대 결과: 무엇이 보여야 하는지
3. 실제 결과: 현재 무엇이 출력되는지
4. 관련 로그: `inspect` 본문 구간 (`AXRow > AXCell > AXTextArea`) + `trace-ax`

#### 예시 요청

```text
kmsg read가 메시지 본문 대신 시간/숫자를 출력합니다.
inspect 결과를 기준으로 AXRow > AXCell > AXTextArea.value를 우선 추출하도록 수정해 주세요.
README 디버깅 가이드도 함께 업데이트해 주세요.
```

## Deploy

`v*` 태그를 푸시하면 GitHub Actions가 자동으로 빌드해서
`kmsg-macos-universal` 파일을 Releases에 업로드합니다.

배포 전에 `VERSION` 파일 값을 먼저 업데이트하세요.

```bash
# gh 토큰이 만료됐으면 재로그인
gh auth login -h github.com

# 배포 태그 생성/푸시
git tag v0.1.3
git push origin v0.1.3
```

필요하면 Actions를 수동 실행할 수 있습니다.

```bash
gh workflow run release.yml -f tag=v0.1.3
```

## 기타

- 설치는 `kmsg-macos-universal` 을 사용합니다.
- 다운로드 실패 시 https://github.com/channprj/kmsg/releases 에서 직접 내려받아 `~/.local/bin/kmsg`로 저장 후 `chmod +x ~/.local/bin/kmsg` 를 진행하시면 됩니다.

## Inspiration

This project is strongly inspired by [steipete](https://github.com/steipete) and his works.

- [imsg](https://github.com/steipete/imsg)
- [openclaw](https://github.com/openclaw/openclaw)

## References

- https://github.com/steipete/imsg

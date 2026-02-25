# kmsg

macOS용 KakaoTalk CLI 도구입니다. Accessibility API를 사용하여 카카오톡을 제어합니다.

## 기능

- 카카오톡 상태 확인
- 채팅방 목록 조회
- 메시지 보내기
- 메시지 읽기
- UI 구조 검사 (디버깅용)

## 요구사항

- macOS 13.0 이상
- macOS용 KakaoTalk 설치
- Accessibility 권한 허용 (최초 실행 시 자동 요청)

## 설치

### 1. 빌드

```bash
# 저장소 클론
git clone https://github.com/channprj/kmsg.git
cd kmsg

# 빌드 (Debug)
swift build

# 빌드 (Release - 최적화됨)
swift build -c release
```

### 2. 실행 파일 위치

```bash
# Debug 빌드
.build/debug/kmsg

# Release 빌드
.build/release/kmsg
```

### 3. 전역 설치 (선택사항)

```bash
mkdir -p ~/.local/bin

# 방금 빌드한 바이너리 설치 (Debug)
install -m 755 .build/debug/kmsg ~/.local/bin/kmsg

# 또는 Release 빌드 설치
install -m 755 .build/release/kmsg ~/.local/bin/kmsg

# 쉘 설정 파일에 PATH 추가 (~/.zshrc 또는 ~/.bashrc)
export PATH="$HOME/.local/bin:$PATH"
```

## 권한 설정

kmsg는 카카오톡을 제어하기 위해 Accessibility 권한이 필요합니다.

`kmsg` 실행 시 권한이 없으면:

1. Accessibility 권한 요청 팝업을 자동으로 띄웁니다.
2. 필요하면 **시스템 설정 > 개인정보 보호 및 보안 > 손쉬운 사용** 화면을 자동으로 엽니다.
3. 최종 허용은 사용자가 직접 토글해야 합니다.

## 사용법

### 상태 확인

```bash
kmsg                    # 상태 확인 + 사용법 표시
kmsg status             # 상태 확인
kmsg status --verbose   # 상세 정보 포함
```

### 채팅방 목록

```bash
kmsg chats              # 채팅방 목록
kmsg chats --verbose    # 상세 정보 포함
kmsg chats --trace-ax   # AX 탐색/재시도 추적 로그
```

### 메시지 보내기

```bash
kmsg send "친구이름" "안녕하세요!"
kmsg send "그룹채팅방" "메시지" --dry-run   # 테스트 (실제 전송 안함)
kmsg send "친구이름" "안녕하세요!" --trace-ax # 입력/전송 단계 추적 로그
kmsg send "친구이름" "안녕하세요!" --close-after-send # 전송 후 채팅창 닫기
kmsg send "친구이름" "안녕하세요!" --refresh-cache # AX 경로 캐시 재생성
kmsg send "친구이름" "안녕하세요!" --no-cache      # 캐시 없이 1회 실행
```

`--trace-ax` 로그에는 윈도우 복구 전략(`focusedWindow -> mainWindow -> windows.first`)과 재시도 경로가 표시됩니다.

성능 튜닝이 필요하면 AX 호출 타임아웃(초)을 환경변수로 조정할 수 있습니다.

```bash
KMSG_AX_TIMEOUT=0.25 kmsg send "친구이름" "메시지"
```

### AX 캐시 관리

`kmsg`는 자주 쓰는 AX 경로(검색 입력, 메시지 입력)를 `~/.kmsg/ax-cache.json`에 저장해 다음 실행 속도를 높입니다.

```bash
kmsg cache status               # 캐시 상태 확인
kmsg cache clear                # 캐시 삭제
kmsg cache warmup --recipient "송요섭"  # 첫 전송 전에 경로 워밍업
kmsg cache export ./ax-cache.json
kmsg cache import ./ax-cache.json
```

### 메시지 읽기

```bash
kmsg read "친구이름"              # 최근 메시지 읽기
kmsg read "친구이름" --limit 50   # 최근 50개 메시지
kmsg read "친구이름" --trace-ax   # AX 탐색 추적 로그
```

### UI 검사 (디버깅)

```bash
kmsg inspect                          # 메인 윈도우 검사
kmsg inspect --window 1 --depth 5     # 특정 윈도우, 깊이 5
kmsg inspect --show-attributes        # 모든 속성 표시
```

## 작동 원리

kmsg는 macOS Accessibility API (`AXUIElement`)를 사용하여 카카오톡 UI와 상호작용합니다.

- 카카오톡 프로토콜 리버스 엔지니어링 없음
- 공식 macOS용 카카오톡 앱과 호환
- 사용자 개인정보 보호

## 라이선스

MIT License - [LICENSE](LICENSE) 참조

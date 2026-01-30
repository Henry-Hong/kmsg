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
- Accessibility 권한 허용

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
cp .build/release/kmsg ~/.local/bin/

# 쉘 설정 파일에 PATH 추가 (~/.zshrc 또는 ~/.bashrc)
export PATH="$HOME/.local/bin:$PATH"
```

## 권한 설정

kmsg는 카카오톡을 제어하기 위해 Accessibility 권한이 필요합니다.

1. **시스템 설정** > **개인정보 보호 및 보안** > **손쉬운 사용** 열기
2. **+** 버튼 클릭
3. `kmsg` 실행 파일 선택
4. 토글 활성화

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
```

### 메시지 보내기

```bash
kmsg send "친구이름" "안녕하세요!"
kmsg send "그룹채팅방" "메시지" --dry-run   # 테스트 (실제 전송 안함)
```

### 메시지 읽기

```bash
kmsg read "친구이름"              # 최근 메시지 읽기
kmsg read "친구이름" --limit 50   # 최근 50개 메시지
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

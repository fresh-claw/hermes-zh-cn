# Xiaoma AI Hermes 중국어 강화 패키지

[中文主页](README.md)

이 저장소는 [Hermes Agent](https://github.com/NousResearch/hermes-agent)를 위한 중국어 강화 패키지를 제공합니다.

사용자는 Hermes에 다음 문장을 보낼 수 있습니다.

```text
请访问 useai.live/hermes 安装汉化补丁
```

Hermes는 공개 페이지를 읽고 설치 안내를 찾은 뒤 다음 설치 프로그램을 실행할 수 있습니다.

```bash
curl -fsSL https://useai.live/hermes/install.sh | bash
```

## 기능

설치 프로그램은 로컬 Hermes 버전을 감지합니다. Hermes가 없으면 공식 Hermes를 먼저 설치한 뒤, 맞는 중국어 강화 패키지를 적용합니다.

`display.language=zh`를 설정하고, Xiaoma AI 보조 스킬, 시작 전 업데이트 도우미, 공식 언어 설정에 아직 연결되지 않은 UI 문구용 백업 포함 패치를 추가합니다.

## 적용 범위

- 시작 제목을 중국어 `爱马仕机器人`으로 변경.
- 원본 스타일의 점자형 엠블럼 유지.
- 슬래시 명령 설명 중국어화.
- 도구 분류와 스킬 분류 중국어화.
- 주요 TUI 안내와 실행 진행 메시지 중국어화.
- Hermes `0.2`부터 `0.12`까지의 이전 버전 지원.
- 현재 `0.13.x` 패키지 지원.

## 경계

- 사용자 대화를 읽지 않습니다.
- API 키를 읽지 않습니다.
- 모델 응답을 변경하지 않습니다.
- 타사 도구의 원본 출력을 변경하지 않습니다.

## 파일

```text
web/install.sh               설치 프로그램
web/latest.json              버전 정보
web/packages/0.13.x/zh-CN/   현재 패키지
web/packages/legacy/zh-CN/   이전 버전 호환 패키지
tools/xiaoma-hermes          상태 및 업데이트 도우미
```

웹사이트는 중국어로 유지합니다. 이 한국어 문서는 GitHub에만 게시합니다.

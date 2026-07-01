# AI 개발 파이프라인 요구사항 명세서

> 원본: `codex-claude-cli-pipeline-setup-prompt.md`
> 작성일: 2026-07-01
> 문서 성격: 로컬 AI 개발 파이프라인(Codex Planner + Claude CLI Builder) 셋팅 요구사항 명세

---

## 1. 개요

### 1.1 목적
사용자의 자연어 개발 요청을 **Codex가 분석·계획**하고, **Claude CLI가 실제 코드를 구현**하는 단순 로컬 파이프라인을 셋팅한다. 단일 진입점 명령으로 전체 흐름을 구동하는 것이 최종 목표다.

```bash
./scripts/ai-dev.sh "사용자 개발 요청"
```

### 1.2 역할 분리 (핵심 설계 원칙)
| 구성요소 | 역할 | 책임 | 금지 |
|----------|------|------|------|
| **Codex** | Planner | 요청 판별, 요구사항 구체화, 개발 계획 수립, 구현 프롬프트 생성 | 코드 수정, 테스트 실행, Claude 직접 호출 |
| **Claude CLI** | Builder | 승인된 계획 기반 실제 코드 구현, 테스트 | 범위 초과 리팩터링, 임의 스키마/API 변경 |
| **사람(User)** | Gate | 실행 승인, git diff 검토, commit 결정 | — |

### 1.3 전체 동작 흐름
```text
사용자 프롬프트 입력
 → Codex가 개발 명령인지 판별
 → Codex가 요구사항 구체화 및 개발 플랜 생성
 → Codex가 Claude CLI용 구현 프롬프트 생성
 → [사람 승인 게이트]  (y/N)
 → Claude CLI가 실제 코드 구현
 → 구현 결과와 로그 저장
 → 사람이 git diff 확인
```

---

## 2. 셋팅 작업 제약 조건 (Setup Constraints)

셋팅 담당자(Codex)가 파이프라인 파일을 생성할 때 반드시 지켜야 하는 원칙.

- **SC-1** 기존 애플리케이션 코드는 수정하지 않는다.
- **SC-2** 이번 작업은 AI 파이프라인 셋팅 파일만 추가한다.
- **SC-3** 동일 파일이 존재하면 내용을 확인하고, 기존 프로젝트 규칙을 해치지 않게 병합·보완한다.
- **SC-4** 실행 가능한 shell script를 작성한다.
- **SC-5** Codex(Planner) / Claude CLI(Builder) 역할을 분리한다.
- **SC-6** Claude CLI 자동 호출 전 반드시 사용자 승인 게이트를 둔다.
- **SC-7** 생성 후 변경 파일 목록과 사용 방법을 요약한다.

---

## 3. 산출물 (Deliverables)

### 3.1 최종 파일 구조
```text
project-root/
  AGENTS.md                         # Codex(Planner) 역할·규칙 정의
  CLAUDE.md                         # Claude Code(Builder) 역할·규칙 정의

  .agents/
    skills/
      dev-planner/
        SKILL.md                    # 개발요청 판별·계획 수립 스킬

  scripts/
    ai-dev.sh                       # 파이프라인 진입 스크립트

  docs/
    ai/
      runs/
        .gitkeep                    # 실행 산출물 저장 디렉터리 유지용
```

### 3.2 산출물별 요구사항

| ID | 파일 | 요구사항 요약 |
|----|------|---------------|
| D-1 | `.agents/skills/dev-planner/SKILL.md` | 개발요청 판별 + 요구사항 구체화 + 계획/구현 프롬프트 생성 스킬 정의 |
| D-2 | `AGENTS.md` | Codex의 Planner 역할, 제한사항, 계획/리뷰 기준 정의 |
| D-3 | `CLAUDE.md` | Claude의 Builder 역할, 구현 전 확인·구현 원칙·금지사항·출력형식 정의 |
| D-4 | `scripts/ai-dev.sh` | 전체 파이프라인 오케스트레이션 bash 스크립트 |
| D-5 | `docs/ai/runs/.gitkeep` | 빈 파일 (디렉터리 유지) |

---

## 4. 기능 요구사항 (Functional Requirements)

### 4.1 dev-planner Skill (D-1)

**FR-1.1 출력 형식**
- Codex는 반드시 **순수 JSON**으로만 출력한다. JSON 앞뒤 설명문·Markdown 코드블록·주석 금지.

**FR-1.2 개발 요청인 경우 스키마**
```json
{
  "is_development_request": true,
  "request_summary": "",
  "requirements": [],
  "assumptions": [],
  "questions": [],
  "scope": { "included": [], "excluded": [] },
  "development_plan": [
    { "step": 1, "title": "", "description": "",
      "expected_files": [], "test_criteria": [] }
  ],
  "acceptance_criteria": [],
  "risk_notes": [],
  "claude_prompt": ""
}
```

**FR-1.3 개발 요청이 아닌 경우 스키마**
```json
{ "is_development_request": false, "answer": "사용자에게 직접 응답할 내용" }
```

**FR-1.4 개발 명령 판별 기준**
- 개발 명령으로 판단: 기능 추가 / 버그 수정 / 리팩터링 / 테스트 추가 / 코드 구조 변경 / API·UI·DB·배치·설정 변경 / 성능·보안·로깅·예외처리 개선.
- 일반 질문으로 판단: 개념 설명 / 단순 질의응답 / 코드 수정 없는 의견 / 문서 번역·요약 / 실행 불필요한 검토.
- "수정해줘 / 구현해줘 / 추가해줘 / 반영해줘 / 고쳐줘" 표현은 개발 명령 가능성이 높음.

**FR-1.5 `claude_prompt` 필수 포함 항목**
1. 구현 목표 2. 변경 범위 3. 제외 범위 4. 구현 순서 5. 테스트 기준 6. 금지 사항 7. 구현 후 요약 형식

**FR-1.6 Claude에게 강제할 사항** (프롬프트 내 명시)
- `git status` 우선 확인 / 변경 전 관련 파일 탐색 / 승인 범위만 구현 / 불필요 리팩터링 금지 / Secret·API Key·Token 하드코딩 금지 / 가능 시 테스트 실행 / 변경 파일·테스트 결과 출력.

**FR-1.7 보안·품질 고려 항목** (계획 수립 시)
- 인증/인가 영향, 개인정보·민감정보 노출, 로그 출력 영향, 외부 API 영향, DB schema 변경 여부, public API contract 영향, 테스트 누락, 롤백 가능성.

### 4.2 ai-dev.sh 스크립트 (D-4)

**FR-2.1 입력 검증**
- 사용자 프롬프트를 인자로 받는다. 인자 없으면 사용법 출력 후 종료(exit 1).
  ```text
  사용법: ./scripts/ai-dev.sh "개발 요청 내용"
  ```

**FR-2.2 의존성 확인**
- `codex`, `claude`, `python` CLI 존재 여부를 확인하고, 없으면 안내 후 종료.

**FR-2.3 실행 로그 관리**
- `RUN_ID = date +%Y%m%d-%H%M%S`
- 실행 산출물을 `docs/ai/runs/{RUN_ID}/`에 저장.
- 원본 프롬프트를 `user-prompt.txt`로 저장.

**FR-2.4 Codex 실행**
- `codex exec --sandbox read-only` (read-only 샌드박스)로 실행.
- 결과를 `codex-plan.raw`에 저장. 실패 시(exit≠0) 원본 경로 안내 후 종료.

**FR-2.5 JSON 파싱**
- Python으로 raw 출력에서 JSON 추출(순수 JSON / 코드펜스 / 첫 `{`~마지막 `}` 순으로 시도).
- 성공 시 `codex-plan.json`(indent=2, ensure_ascii=False)으로 저장.
- **파싱 실패 시 원본 파일 경로·에러 표시 후 중단.**

**FR-2.6 요청 분기**
- `is_development_request == false` → `answer` 출력 후 종료 (Claude 미호출).
- `true` → 플랜 요약(요약/요구사항/가정/질문/작업계획/리스크) 출력.

**FR-2.7 승인 게이트**
- `y/N` 프롬프트로 사용자 승인 수집.
- `y` 또는 `Y`가 아니면 중단하고 Codex 결과 저장 위치 안내.

**FR-2.8 Claude 구현 프롬프트 생성**
- `claude_prompt`가 비어 있으면 오류 종료.
- 전체 개발계획 JSON + `claude_prompt` + 추가 규칙(git status 확인, 파일 탐색, 범위 준수, dependency·Secret 금지, 테스트 실행/사유, 결과 요약)을 합쳐 `claude-prompt.md`로 저장.

**FR-2.9 Claude 실행**
- `claude -p "<prompt>" --allowedTools "Read,Edit,Bash" --append-system-prompt-file CLAUDE.md` 실행.
- 출력을 `claude-result.md`에 `tee`로 저장.
- 실패(`PIPESTATUS[0]`≠0) 시 결과 파일 안내 후 종료.

**FR-2.10 완료 안내**
- 결과 디렉터리 안내 및 `git diff --stat` / `git diff` 확인 명령 안내.

### 4.3 산출물 저장 규격 (D-4 결과)
```text
docs/ai/runs/{timestamp}/
  user-prompt.txt      # 사용자 원본 개발 요청
  codex-plan.raw       # Codex 원본 출력
  codex-plan.json      # 파싱된 Codex 개발 계획
  claude-prompt.md     # Claude에 전달한 최종 구현 프롬프트
  claude-result.md     # Claude 실행 결과
```

---

## 5. 비기능 요구사항 (Non-Functional Requirements)

- **NFR-1 안정성**: 스크립트는 `set -euo pipefail`로 오류 시 즉시 중단.
- **NFR-2 안전성**: Codex는 read-only 샌드박스로만 실행 (계획 단계에서 코드 변경 불가).
- **NFR-3 사람 개입(Human-in-the-loop)**: Claude 자동 호출 전 승인 게이트 필수.
- **NFR-4 추적성**: 모든 실행은 타임스탬프 디렉터리에 전체 산출물 보존.
- **NFR-5 멱등·비파괴**: 자동 commit/merge 금지. 변경은 사람이 diff 확인 후 수동 commit.
- **NFR-6 이식성**: bash + python 기반 로컬 실행 (외부 서비스 의존 없음).

---

## 6. 검증 기준 (Acceptance Criteria)

- **AC-1** 5개 산출물이 명시된 경로에 모두 생성된다.
- **AC-2** `scripts/ai-dev.sh`에 실행 권한 부여(`chmod +x`).
- **AC-3** 인자 없이 실행 시 사용법 메시지 출력.
  ```bash
  ./scripts/ai-dev.sh
  # → 사용법: ./scripts/ai-dev.sh "개발 요청 내용"
  ```
- **AC-4** 개발 요청 입력 시: Codex 분석 → 플랜 요약 → 승인 게이트 → (승인 시) Claude 구현 → 산출물 저장 흐름이 정상 동작.
- **AC-5** 비개발 요청 입력 시: Codex `answer`만 출력하고 Claude 미호출.
- **AC-6** JSON 파싱 실패 시 원본 표시 후 중단.

---

## 7. 리스크 및 주의 사항 (PoC 한계)

이 파이프라인은 **PoC 용도**이며 초기 운영 시 다음을 준수한다.

1. 대규모 리팩터링에 즉시 사용하지 않는다.
2. 인증/인가/결제/DB schema 변경 작업에 즉시 적용하지 않는다.
3. 초기에는 작은 validation·메시지 수정·테스트 보강으로 검증한다.
4. Claude 실행 전 항상 Codex 계획을 사람이 확인한다.
5. Claude 실행 후 항상 `git diff`를 사람이 확인한다.
6. 자동 commit·자동 merge를 하지 않는다.

### 7.1 환경 관련 확인 필요 사항 ⚠️
- 현재 프로젝트는 **git 저장소가 아님** → `git diff` 검토 흐름을 쓰려면 `git init` 필요.
- 실행 환경이 **Windows(win32) / PowerShell** → `ai-dev.sh`(bash)는 Git Bash 또는 WSL에서 실행해야 함. `chmod +x`는 Windows 네이티브에서 무의미.
- `codex`, `claude`, `python` CLI 설치·로그인 상태 사전 확인 필요.

---

## 8. 셋팅 후 최종 보고 형식

셋팅 완료 시 다음 형식으로 보고한다.
1. 생성/수정 파일 목록 (5개 산출물)
2. 사용 방법 (`./scripts/ai-dev.sh "개발 요청 내용"`)
3. 동작 흐름 요약
4. 다음 확인 사항: Codex 로그인 / Claude 로그인 / 실행 권한 / 소규모 PoC 실행

---

## 9. 사용 예시

```bash
./scripts/ai-dev.sh "로그인 실패 시 실패 횟수를 증가시키고, 5회 이상 실패하면 계정을 잠금 처리하도록 수정해줘"
```
예상 흐름: Codex 분석 → 개발요청 판단 → 요구사항·가정·질문·계획 출력 → 승인 요청 → (y) Claude 구현 → `docs/ai/runs/{timestamp}/` 저장 → git diff 확인.

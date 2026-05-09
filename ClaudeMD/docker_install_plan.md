# Windows Docker Desktop 자동 설치 스크립트 계획서

작성일: 2026-05-07
대상 프로젝트: `C:\Users\user\Desktop\linux_shared_folder\ServerCore`

---

## 1. 목표

> **"방금 사놓은 Windows PC"에서 단일 .bat 파일을 실행하면 ServerCore 빌드에 필요한 Docker 환경이 전부 셋업되는 것**

- 사용자는 `setup_docker_windows.bat`을 더블클릭만 하면 됨
- 스크립트가 끝난 시점에 `Scripts\Docker\Linux\Debug\debug_build.bat` 더블클릭으로 즉시 빌드 가능 상태
- 멱등성: 이미 설치된 항목은 skip하고 진행
- 명시적 진행 로그로 어느 단계에서 실패했는지 파악 가능

---

## 2. Windows에서 Docker Desktop 사용을 위한 의존성 분석

### 2.1 필수 (자동화 가능)

| 항목 | 역할 | 설치 방법 |
|------|------|-----------|
| **WSL2** | Docker Desktop 기본 백엔드 (Hyper-V 백엔드도 있으나 WSL2 권장) | `wsl --install --no-distribution` (Windows 10 2004+ / 11 기본 제공) |
| Windows feature: `VirtualMachinePlatform` | WSL2 가상화 기반 | `wsl --install`이 자동 활성화 (또는 `dism` 명시 호출) |
| Windows feature: `Microsoft-Windows-Subsystem-Linux` | WSL 핵심 | 동상 |
| WSL2 kernel update | WSL2 커널 갱신 (구버전 Windows에서만) | Windows Update 또는 `wsl --update` |
| **Docker Desktop** | 컨테이너 엔진 본체 | `winget install --id=Docker.DockerDesktop -e --accept-package-agreements --accept-source-agreements` |

### 2.2 필수 (자동화 불가 — 사용자 안내)

| 항목 | 이유 | 안내 |
|------|------|------|
| **CPU 가상화 (BIOS/UEFI)** | Intel VT-x / AMD-V | OS 내에서 활성화 불가. BIOS 진입 후 "Intel Virtualization Technology" / "SVM Mode" 활성화 안내 (감지: `systeminfo \| findstr "Virtualization"`) |
| **재부팅** | WSL feature 활성화 후 필수 | 스크립트가 명시적으로 "지금 재부팅 후 같은 .bat 다시 실행" 안내 |
| **Docker Desktop 라이선스 동의** | 첫 실행 시 GUI 동의 필요 (Docker Subscription Service Agreement) | 스크립트가 Docker Desktop을 띄우고 "GUI에서 Accept를 누르라"고 안내 |

### 2.3 선택 (편의)

| 항목 | 이유 | 자동 설치? |
|------|------|------------|
| Git for Windows | 리포 clone | 이 스크립트를 받았다는 건 이미 있다고 가정 |
| Windows Terminal | UX 개선 | 선택. winget으로 `Microsoft.WindowsTerminal` 설치 가능 |

---

## 3. 자동화 전략 비교

| 방법 | 장점 | 단점 | 채택 |
|------|------|------|------|
| **winget** (Windows Package Manager) | Windows 10 1809+/11 기본 제공, 의존성 자동 해결, 멱등성 좋음 | 매우 오래된 Windows에는 미설치 | **1순위** |
| Chocolatey | 풍부한 패키지, 멱등성 우수 | 별도 부트스트랩 필요 (PowerShell 1줄) | 2순위 (winget 미존재 시 fallback) |
| 수동 다운로드 + silent install | 외부 의존성 0 | 코드 길어짐, 버전 추적 직접 | 3순위 (winget/choco 다 안 될 때) |

> **채택**: `winget`이 사용 가능하면 winget, 없으면 수동 다운로드(`Invoke-WebRequest` + `Docker Desktop Installer.exe install --quiet --accept-license`)로 fallback.

---

## 4. 스크립트 명세

### 4.1 파일 위치 / 이름

`Scripts\Setup\setup_docker_windows.bat` (신규 디렉터리 `Scripts\Setup\`)

> 빌드 진입점(`Scripts\Docker\`)과 분리. 빌드 vs 환경 셋업의 의도를 디렉터리 레벨에서 구분.

### 4.2 동작 순서

```
[1] 관리자 권한 확인
    ├─ 권한 없음 → PowerShell `Start-Process -Verb RunAs`로 자체 재실행
    └─ 있음 → 다음 단계

[2] CPU 가상화 활성화 여부 점검
    ├─ systeminfo로 "Virtualization Enabled In Firmware" 확인
    └─ Disabled → 사용자에게 BIOS 진입 안내 후 종료

[3] Windows 버전 확인
    ├─ 10 build 19041 미만 → "Windows 업데이트 후 재시도" 안내 종료
    └─ OK → 다음

[4] WSL 상태 점검
    ├─ `wsl --status` 정상 응답 → skip
    └─ 미설치/오류 →
        ├─ `wsl --install --no-distribution` 실행
        └─ "재부팅 후 같은 .bat 다시 실행" 안내 + 종료 (exit 10)

[5] Docker Desktop 설치 점검
    ├─ `docker --version` 응답 OR `C:\Program Files\Docker\Docker\Docker Desktop.exe` 존재 → skip
    └─ 미설치 →
        ├─ winget 사용 가능 → `winget install --id=Docker.DockerDesktop -e --accept-package-agreements --accept-source-agreements`
        ├─ winget 실패/미존재 → 수동 fallback:
        │     ├─ `Invoke-WebRequest -Uri https://desktop.docker.com/win/main/amd64/Docker%20Desktop%20Installer.exe -OutFile $env:TEMP\DockerInstaller.exe`
        │     └─ `Start-Process -Wait $env:TEMP\DockerInstaller.exe -ArgumentList 'install','--quiet','--accept-license'`
        └─ 재부팅 권고 (필수는 아니나 권장) + exit 11

[6] Docker Desktop 실행
    ├─ 이미 떠 있음 (Get-Process Docker Desktop) → skip
    └─ 안 떠 있음 → `Start-Process "C:\Program Files\Docker\Docker\Docker Desktop.exe"`

[7] Docker daemon 준비 대기 (최대 90초 폴링)
    ├─ `docker info` 0초 간격 5초씩 12회 시도
    ├─ 성공 → 다음
    └─ 90초 초과 →
        └─ "Docker Desktop GUI에서 라이선스 동의(Accept)를 눌러주세요" 안내 후 재시도

[8] 검증 빌드 (선택, --skip-verify로 건너뛰기 가능)
    ├─ `docker run --rm hello-world` 실행
    └─ 성공 시 [SUCCESS] 메시지 + 빌드 진입점 안내

[9] 완료 메시지
    ────────────────────────────────────────
    [DONE] Docker 환경 셋업 완료.
    다음 단계:
      Scripts\Docker\Linux\Debug\debug_build.bat   (Linux 풀빌드)
      Scripts\Docker\Windows\Debug\debug_build.bat (Windows 풀빌드)
    ────────────────────────────────────────
```

### 4.3 멱등성 보장

- 매 단계가 "이미 있음"을 먼저 검사하고 skip
- 두 번째 실행은 [4]까지 모두 skip하고 [6]에서 Docker Desktop 시작만 시도 후 끝
- 삼중 안전장치: `setup_docker_windows.bat` 자체를 여러 번 돌려도 부작용 없음

### 4.4 종료 코드 규약

| exit | 의미 | 사용자 액션 |
|------|------|-------------|
| 0    | 모든 단계 성공 | 빌드 시작 |
| 1    | 일반 에러 (로그 확인 필요) | 로그 보고 재시도 |
| 2    | CPU 가상화 비활성 | BIOS에서 활성화 후 재실행 |
| 3    | Windows 버전 미달 | Windows Update 후 재실행 |
| 10   | WSL 설치 후 재부팅 필요 | 재부팅 후 같은 .bat 재실행 |
| 11   | Docker Desktop 설치 후 재부팅 권장 | 재부팅 후 재실행 (또는 [6]부터 수동 진행) |
| 20   | Docker daemon이 90초 내 안 뜸 | Docker Desktop GUI 라이선스 동의 후 재실행 |

### 4.5 옵션 인자

```
setup_docker_windows.bat [--skip-verify] [--no-start] [--quiet]
```

- `--skip-verify`: `docker run hello-world` 검증 건너뛰기 (CI / 인터넷 제한 환경)
- `--no-start`: Docker Desktop을 띄우지 않음 (설치만)
- `--quiet`: 진행 메시지 최소화

---

## 5. 사용자 시나리오

### 5.1 깨끗한 Windows 11 PC (BIOS 가상화 OFF)

```
1. git clone <repo>
2. Scripts\Setup\setup_docker_windows.bat 더블클릭
   → [2] CPU 가상화 비활성 감지 → exit 2 + BIOS 진입 안내
3. 재부팅 → BIOS에서 VT-x 활성화
4. Scripts\Setup\setup_docker_windows.bat 재실행
   → [4] WSL 설치 → exit 10 + 재부팅 안내
5. 재부팅
6. Scripts\Setup\setup_docker_windows.bat 재실행
   → [5] Docker Desktop winget 설치 → exit 11
7. 재부팅 (선택)
8. Scripts\Setup\setup_docker_windows.bat 재실행
   → [6] Docker Desktop 시작
   → [7] Daemon 준비 (라이선스 동의 안내가 떠있다면 사용자가 GUI에서 Accept)
   → [8] hello-world 검증 OK
   → [DONE]
9. Scripts\Docker\Linux\Debug\debug_build.bat 실행 → 빌드 시작
```

### 5.2 이미 WSL2 + Docker Desktop이 있는 PC

```
1. setup_docker_windows.bat 실행
   → [4] skip [5] skip [6] skip (또는 시작) [7] OK [8] OK [DONE]
   총 ~30초
```

### 5.3 BIOS 진입 권한이 없는 회사 PC

```
1. setup_docker_windows.bat
   → [2] 가상화 비활성 → exit 2 + BIOS 안내
2. 사용자가 IT부서에 가상화 활성화 요청
3. 활성화 후 다시 시작
```

---

## 6. 실패 모드 / 사전 점검

| 위험 | 완화책 |
|------|--------|
| BIOS 가상화가 OFF인데 사용자가 모르고 진행 | [2]에서 명시적으로 감지 + BIOS 키 (Del/F2 등) 안내 |
| WSL 설치 후 재부팅 안 한 채 다음 단계 진행 시 wsl 명령 실패 | [4]에서 wsl --install 후 무조건 exit 10 + 안내 |
| winget 자체가 미설치 (오래된 Windows 10) | 수동 fallback (Invoke-WebRequest로 인스톨러 직접 다운로드) |
| Docker Desktop 라이선스 동의 미완료로 daemon이 안 뜸 | [7]에서 90초 polling + GUI 동의 안내 |
| Docker Desktop 첫 실행 시 WSL 통합 옵션 묻는 다이얼로그 | 사용자 GUI 클릭 필요 — 안내 |
| 관리자 권한 없이 더블클릭 | [1]에서 자체 UAC 승격 (PowerShell `Start-Process -Verb RunAs`) |
| 한글 Windows 환경의 경로 인코딩 | bat 파일을 CP949로 저장 + `chcp 65001`로 UTF-8 출력 |
| 사내 프록시로 winget 차단 | `--quiet`/`--no-verify` 옵션 + 수동 다운로드 안내 메시지 |
| HOME 디렉터리에 한글/공백 (`C:\Users\사용자\...`) | Docker Desktop은 영향 없으나 명시적으로 호스트 경로 점검 권고 (단순 경고) |

---

## 7. 단계별 도입 로드맵

### PHASE 0 — 디렉터리 구조 준비

1. `Scripts\Setup\` 디렉터리 생성
2. README의 "사전 준비" 섹션에 `setup_docker_windows.bat` 안내 추가

### PHASE 1 — 핵심 .bat 작성

1. `Scripts\Setup\setup_docker_windows.bat` 작성 (4.2 동작 순서 그대로)
2. 진행 메시지 한글화 (CP949 + `chcp 65001` UTF-8 코드페이지)
3. 멱등성 테스트 (이미 모두 설치된 PC에서 두 번 돌려도 OK)
4. 종료 코드별 안내 메시지 검증

**검증 기준 (PHASE 1 완료 조건)**:
- 깨끗한 Windows 11 VM에서 시나리오 5.1을 끝까지 수행 → 빌드 성공
- 이미 셋업된 PC에서 재실행 → 30초 안에 [DONE] 도달

---

## 8. 신규 / 변경 파일 요약

| 파일 | 역할 |
|------|------|
| `Scripts/Setup/setup_docker_windows.bat` | Windows Docker 환경 자동 셋업 (이 계획의 결과물) |
| `README.md` | "사전 준비" 섹션에 `setup_docker_windows.bat` 한 줄 안내 추가 |
| `ClaudeMD/docker_install_plan.md` | 이 문서 |

---

## 9. 한 줄 요약

`Scripts\Setup\setup_docker_windows.bat` 한 번 실행으로,
**WSL2 활성화 → Docker Desktop 설치(winget) → daemon 준비 → hello-world 검증**까지 자동 수행하고,
재부팅이 필요한 단계마다 명시적 exit 코드 + 안내로 사용자를 끊김 없이 가이드한다.
끝나면 `Scripts\Docker\<OS>\<Mode>\<group>_build.bat` 더블클릭으로 즉시 빌드 가능.

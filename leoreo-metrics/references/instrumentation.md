# 계측 부록 — 스키마와 쿼리

> SQL은 PostgreSQL 문법 기준. 스키마 이름은 각 프로젝트에 맞게 바꿔 씁니다.

## 1. 이벤트 스키마

### 공통 프로퍼티 (모든 이벤트 필수)

| 필드 | 설명 | 주의 |
|---|---|---|
| `event_name` | `대상_행동` 과거형 (`checkout_started`) | 이름은 한 번 정하면 바꾸지 않습니다. 바꿔야 하면 새 이름 + `schema_version` |
| `user_id` | 로그인 사용자 식별자 | 개인정보가 아닌 내부 ID |
| `anonymous_id` | 비로그인 식별자 | 가입 시점에 `user_id`와 이어 붙여야 유입→가입 퍼널이 이어집니다 |
| `occurred_at` | **서버 기준** 발생 시각 (UTC) | 클라이언트 시각은 기기 시계 오차로 코호트를 망칩니다. 받아두되 별도 필드로 |
| `source` | `web` / `ios` / `android` / `server` | 유실률이 소스마다 다르므로 분리 필수 |
| `schema_version` | 정수 | 스키마를 바꿔도 과거 데이터를 살립니다 |

### AARRR 단계별 최소 이벤트 셋

| 단계 | 이벤트 | 핵심 프로퍼티 |
|---|---|---|
| Acquisition | `signup_completed` | 유입 채널, 캠페인, 추천인 |
| Activation | `onboarding_step_completed`, `aha_moment_reached` | 단계 번호, 가입 후 경과 시간 |
| Retention | 핵심 행동 1개 (`document_created` 등) | 그 서비스를 "쓴다"고 말할 수 있는 유일한 행동 |
| Revenue | `pricing_viewed`, `checkout_started`, `payment_succeeded`, `payment_failed` | 플랜, 금액(정수), 실패 사유 코드 |
| Referral | `invite_sent`, `invite_accepted` | 초대자, 수락자 |
| 확장/축소 | `plan_changed` | 이전 플랜, 다음 플랜, 방향(up/down), 사유 |

### 서버 수집 vs 클라이언트 수집

| 이벤트 종류 | 수집 위치 | 이유 |
|---|---|---|
| 결제·구독·플랜 변경·환불 | **서버 전용** | 광고 차단·앱 종료로 클라이언트 이벤트는 10~30% 유실. 돈 숫자가 틀리면 대시보드 전체 신뢰를 잃습니다 |
| 화면 조회·클릭·스크롤 | 클라이언트 | 서버가 알 수 없는 정보 |
| 온보딩 단계 완료 | 상태가 서버 DB에 남으면 서버, 아니면 클라이언트 | |

돈 관련 지표는 이벤트 로그가 아니라 **결제·구독 원장 테이블**을 정본으로 씁니다. 이벤트는 행동 분석용, 원장은 매출 보고용입니다.

### 개인정보 (개인정보보호법)

- 주민등록번호·카드번호·계좌번호·연락처는 이벤트 프로퍼티에 **넣지 않습니다.**
- 외부 분석 도구를 쓰면 개인정보 처리 위탁에 해당할 수 있습니다. 개인정보처리방침에 수집 항목·위탁받는 자·목적을 적고, 필요하면 위탁 계약을 맺습니다. (2025~2026년 기준이며 개정 가능 — 도입 전 재확인)
- 이벤트에 실명·이메일 대신 내부 ID나 해시값만 보냅니다.

## 2. 코호트 리텐션

가입 주 단위로 묶어 N주 차 잔존을 봅니다. 전체 활성 사용자 수는 신규 유입이 이탈을 가려서 병이 안 보입니다.

```sql
WITH cohorts AS (
  SELECT user_id, DATE_TRUNC('week', created_at) AS cohort_week
  FROM users
),
activity AS (
  SELECT DISTINCT user_id, DATE_TRUNC('week', occurred_at) AS active_week
  FROM events
  WHERE event_name = 'document_created'   -- 핵심 행동 1개로 교체
)
SELECT
  c.cohort_week,
  COUNT(DISTINCT c.user_id) AS cohort_size,
  FLOOR(EXTRACT(EPOCH FROM (a.active_week - c.cohort_week)) / 604800) AS week_n,
  COUNT(DISTINCT a.user_id) AS retained,
  ROUND(100.0 * COUNT(DISTINCT a.user_id) / COUNT(DISTINCT c.user_id), 1) AS retention_pct
FROM cohorts c
LEFT JOIN activity a ON a.user_id = c.user_id AND a.active_week >= c.cohort_week
GROUP BY 1, 3
ORDER BY 1, 3;
```

읽는 법입니다. 세로로 내려가며 각 주차 코호트의 잔존이 좋아지면 제품이 나아지는 중입니다. 가로로 갈 때 **곡선이 어느 지점에서 평평해지는지**를 봅니다. 계속 0으로 떨어지면 아직 제품-시장 적합(PMF) 이전입니다.

## 3. 퍼널

절대 수가 아니라 **구간별 전환율**을 봅니다. 가장 낮은 구간이 `leoreo`가 말하는 병목입니다.

```sql
WITH funnel AS (
  SELECT
    user_id,
    MIN(CASE WHEN event_name = 'pricing_viewed'    THEN occurred_at END) AS t1,
    MIN(CASE WHEN event_name = 'checkout_started'  THEN occurred_at END) AS t2,
    MIN(CASE WHEN event_name = 'payment_succeeded' THEN occurred_at END) AS t3
  FROM events
  WHERE occurred_at >= NOW() - INTERVAL '30 days'
  GROUP BY user_id
)
SELECT
  COUNT(t1) AS viewed,
  COUNT(t2) AS started,
  COUNT(t3) AS paid,
  ROUND(100.0 * COUNT(t2) / NULLIF(COUNT(t1), 0), 1) AS view_to_start_pct,
  ROUND(100.0 * COUNT(t3) / NULLIF(COUNT(t2), 0), 1) AS start_to_paid_pct
FROM funnel;
```

단계 사이 시간(`t2 - t1`)의 중앙값도 함께 봅니다. 전환율은 같은데 시간이 길어지고 있으면 마찰이 늘어난 신호입니다.

## 4. MRR 이동분해

매출 대시보드의 기본형입니다. **좌우가 맞지 않으면 대시보드가 아니라 버그입니다.**

`기초 MRR + 신규 + 확장 − 축소 − 이탈 + 재활성 = 기말 MRR`

```sql
WITH monthly AS (
  SELECT
    DATE_TRUNC('month', period_start) AS month,
    customer_id,
    SUM(amount_krw) AS mrr          -- 금액은 정수(원 단위). float 금지
  FROM subscription_charges
  GROUP BY 1, 2
),
paired AS (
  SELECT
    curr.month,
    curr.customer_id,
    COALESCE(prev.mrr, 0) AS prev_mrr,
    curr.mrr AS curr_mrr
  FROM monthly curr
  LEFT JOIN monthly prev
    ON prev.customer_id = curr.customer_id
   AND prev.month = curr.month - INTERVAL '1 month'
)
SELECT
  month,
  SUM(CASE WHEN prev_mrr = 0 THEN curr_mrr ELSE 0 END)                        AS new_mrr,
  SUM(CASE WHEN prev_mrr > 0 AND curr_mrr > prev_mrr THEN curr_mrr - prev_mrr ELSE 0 END) AS expansion_mrr,
  SUM(CASE WHEN curr_mrr > 0 AND curr_mrr < prev_mrr THEN prev_mrr - curr_mrr ELSE 0 END) AS contraction_mrr,
  SUM(CASE WHEN curr_mrr = 0 AND prev_mrr > 0 THEN prev_mrr ELSE 0 END)       AS churned_mrr
FROM paired
GROUP BY 1
ORDER BY 1;
```

**NRR**은 기존 고객만 봅니다(신규 제외): `(기초 MRR + 확장 − 축소 − 이탈) ÷ 기초 MRR × 100`. 100% 미만이면 밑 빠진 독이고, 신규 획득으로 메우는 구조는 CAC가 오르는 순간 무너집니다.

## 5. 금액을 다룰 때

- **정수(원 단위 bigint)로 저장합니다.** float는 반올림 오차가 누적됩니다 — `leoreo-pay`의 결제 불변식과 같은 규칙입니다.
- 환불·부분취소를 매출에서 언제 빼는지 규칙을 하나로 정합니다. 발생 시점 기준과 원거래 시점 기준이 섞이면 월 매출이 계속 바뀝니다.
- 무료 체험 중인 구독은 MRR에 넣지 않습니다.

## 출처

Amplitude·Mixpanel·PostHog 이벤트 택소노미 가이드, Segment Protocols 명명 규칙, ChartMogul·Baremetrics MRR 이동분해 정의, Lean Analytics(Croll & Yoskovitz) 코호트 분석, 그로스해킹(양승화, 위키북스) AARRR 측정, 개인정보보호법(law.go.kr). 수치·규제는 2025~2026년 기준이며 변동 가능.

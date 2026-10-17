#!/bin/bash
# Wiki.js 3.0 한국어 번역(주요 메뉴 1차, 746개 키) 적용 스크립트
#
# 사용법: 서버 실행 후 이 스크립트가 있는 디렉터리에서
#   ./apply-ko-translation.sh
#
# 환경변수로 다른 인스턴스에 적용할 수 있습니다:
#   WIKI_BASE="http://localhost:3000/_api"   서버 API 주소
#   WIKI_SITE=<uuid>                          사이트 ID (Admin > 사이트에서 확인)
#   WIKI_STRATEGY=<uuid>                      인증 전략 ID (DB authentication 테이블)
#   WIKI_USER=admin@example.com WIKI_PASS=... 로그인 계정
#
# 참고: 위키는 24시간마다 업스트림 로캘을 자동 갱신하므로, 업스트림 한글 번역이
# 게시되기 전까지는 번역이 원본(영어 복사본)으로 덮어씌워질 수 있습니다.
# 그 경우 이 스크립트를 다시 실행하면 복원됩니다.
set -euo pipefail
cd "$(dirname "$0")"

BASE="${WIKI_BASE:-http://localhost:3000/_api}"
SITE="${WIKI_SITE:-f3420665-a487-4fc4-9e03-fd51aefb9c5c}"
STRAT="${WIKI_STRATEGY:-5a528c4c-0a82-4ad2-96a5-2b23811e6588}"
USER="${WIKI_USER:-admin@example.com}"
PASS="${WIKI_PASS:-12345678}"

# PATH에 node가 없으면 이 프로젝트에서 쓰던 포터블 Node 26을 시도
if command -v node >/dev/null 2>&1; then
  NODE=node
elif [ -x /c/dev/wiki-postgres/node26/node.exe ]; then
  NODE=/c/dev/wiki-postgres/node26/node.exe
else
  echo "node를 찾을 수 없습니다. PATH에 추가하거나 NODE 경로를 지정하세요." >&2
  exit 1
fi

COOKIES="$(mktemp)"
trap 'rm -f "$COOKIES"' EXIT

echo "[1/4] 관리자 로그인..."
curl -s -c "$COOKIES" -X PUT "$BASE/sites/$SITE/auth/login" \
  -H "Content-Type: application/json" \
  -d "{\"strategyId\":\"$STRAT\",\"username\":\"$USER\",\"password\":\"$PASS\"}" \
  | grep -q '"authenticated":true' && echo "  로그인 OK" || { echo "  로그인 실패 - 서버가 켜져 있는지 확인하세요"; exit 1; }

echo "[2/4] 번역된 ko-KR.json 업로드 (746개 키)..."
curl -s -b "$COOKIES" -X POST "$BASE/locales/upload?fileName=ko-KR.json" \
  -H "Content-Type: application/json" \
  --data-binary @ko-KR-translated.json
echo

echo "[3/4] 사이트 활성 로캘에 ko-KR 추가..."
curl -s -b "$COOKIES" -X PUT "$BASE/sites/$SITE" \
  -H "Content-Type: application/json" \
  -d '{"locales":{"active":["en","ko-KR"]}}'
echo

echo "[4/4] 적용 확인..."
curl -s "$BASE/locales/ko-KR/strings" > ko-check.json
$NODE -e "
const j=require('./ko-check.json');
const samples=['common.header.home','common.header.search','common.actions.save','auth.actions.login','common.sidebar.mainMenu'];
for(const k of samples) console.log('  '+k+' = '+j[k]);
const ko=Object.values(j).filter(v=>/[가-힣]/.test(v)).length;
console.log('  -> 한글이 채워진 문자열: '+ko+'개 / 총 '+Object.keys(j).length+'개');
"
echo "완료! 브라우저에서 언어 메뉴에서 한국어를 선택하세요."

#!/bin/bash
# ============================================================================
# Multi-Region Shopping Mall - OpenSearch Seed Data
# Creates product search index with nori (Korean) analyzer + bulk index 150 products
# ============================================================================

set -euo pipefail

OS_ENDPOINT="${OPENSEARCH_ENDPOINT:-https://localhost:9200}"
OS_USER="${OPENSEARCH_USER:-admin}"
OS_PASS="${OPENSEARCH_PASS:-Admin@SecurePass123!}"
CURL="curl -s -u ${OS_USER}:${OS_PASS} --insecure"

echo "=== OpenSearch Seed Data ==="
echo "Endpoint: ${OS_ENDPOINT}"

# ── Delete existing index ───────────────────────────────────────────────────
echo "Deleting existing product index..."
$CURL -X DELETE "${OS_ENDPOINT}/products" 2>/dev/null || true

# ── Create index with nori analyzer ─────────────────────────────────────────
echo "Creating product index with nori analyzer..."
$CURL -X PUT "${OS_ENDPOINT}/products" -H 'Content-Type: application/json' -d '{
  "settings": {
    "index": {
      "number_of_shards": 3,
      "number_of_replicas": 1
    },
    "analysis": {
      "analyzer": {
        "korean": {
          "type": "custom",
          "tokenizer": "nori_tokenizer",
          "filter": ["nori_readingform", "lowercase", "nori_part_of_speech_basic"]
        },
        "korean_search": {
          "type": "custom",
          "tokenizer": "nori_tokenizer",
          "filter": ["nori_readingform", "lowercase", "synonym_filter"]
        }
      },
      "filter": {
        "nori_part_of_speech_basic": {
          "type": "nori_part_of_speech",
          "stoptags": ["E", "IC", "J", "MAG", "MAJ", "MM", "SP", "SSC", "SSO", "SC", "SE", "XPN", "XSA", "XSN", "XSV", "UNA", "NA", "VSV"]
        },
        "synonym_filter": {
          "type": "synonym",
          "synonyms": [
            "노트북,랩탑,laptop",
            "핸드폰,스마트폰,휴대폰,phone",
            "냉장고,refrigerator,fridge",
            "세탁기,washing machine",
            "에어컨,에어컨디셔너,air conditioner",
            "청소기,vacuum cleaner",
            "이어폰,이어버드,earphone,earbuds",
            "헤드폰,헤드셋,headphone",
            "신발,운동화,슈즈,shoes,sneakers",
            "가방,백,bag"
          ]
        }
      }
    }
  },
  "mappings": {
    "properties": {
      "productId":   { "type": "keyword" },
      "name":        { "type": "text", "analyzer": "korean", "search_analyzer": "korean_search", "fields": { "keyword": { "type": "keyword" } } },
      "brand":       { "type": "text", "analyzer": "korean", "fields": { "keyword": { "type": "keyword" } } },
      "category":    { "type": "keyword" },
      "categoryName":{ "type": "text", "analyzer": "korean", "fields": { "keyword": { "type": "keyword" } } },
      "description": { "type": "text", "analyzer": "korean" },
      "price":       { "type": "long" },
      "salePrice":   { "type": "long" },
      "discount":    { "type": "integer" },
      "rating":      { "type": "float" },
      "reviewCount": { "type": "integer" },
      "tags":        { "type": "keyword" },
      "status":      { "type": "keyword" },
      "stock":       { "type": "integer" },
      "origin":      { "type": "keyword" },
      "createdAt":   { "type": "date" }
    }
  }
}'
echo ""

# ── Bulk index products ─────────────────────────────────────────────────────
echo "Generating bulk data..."

CATEGORIES=("전자제품" "패션" "식품" "뷰티" "가전" "스포츠" "도서" "반려동물" "가구" "유아용품")
CAT_SLUGS=("electronics" "fashion" "food" "beauty" "appliances" "sports" "books" "pets" "furniture" "baby")

# Product names per category (15 each)
declare -a PRODUCTS
PRODUCTS[0]="삼성 갤럭시 S25 울트라|1799000|삼성전자,아이폰 16 프로 맥스|1990000|Apple,LG 그램 17인치 노트북|2190000|LG전자,삼성 갤럭시 탭 S10|1290000|삼성전자,소니 WH-1000XM6 헤드폰|459000|Sony,에어팟 프로 3세대|359000|Apple,삼성 갤럭시 워치7|399000|삼성전자,아이패드 에어 M3|999000|Apple,로지텍 MX Keys S 키보드|169000|Logitech,삼성 포터블 SSD T9 2TB|279000|삼성전자,JBL 차지5 블루투스 스피커|229000|JBL,닌텐도 스위치 2|449000|Nintendo,PS5 프로 디지털 에디션|799000|Sony,캐논 EOS R50 미러리스|1190000|Canon,삼성 갤럭시 버즈3 프로|299000|삼성전자"
PRODUCTS[1]="나이키 에어맥스 DN|199000|Nike,아디다스 울트라부스트 24|229000|Adidas,유니클로 히트텍 울트라웜|39900|UNIQLO,자라 오버사이즈 블레이저|159000|ZARA,뉴발란스 993 러닝화|259000|New Balance,노스페이스 눕시 패딩|369000|The North Face,구찌 마몽 숄더백|2890000|Gucci,리바이스 501 오리지널 진|129000|Levis,폴로 랄프로렌 케이블 니트|289000|Polo,컨버스 척테일러 올스타|69000|Converse,무신사 스탠다드 맨투맨|29900|무신사,MLB 뉴욕양키스 볼캡|39900|MLB,디스커버리 롱패딩|459000|Discovery,코오롱 안타티카 패딩|699000|KOLON,빈폴 체크 셔츠|119000|BEANPOLE"
PRODUCTS[2]="곰표 밀가루 2.5kg|5900|대한제분,농심 신라면 멀티팩|4980|농심,오뚜기 진라면 매운맛|4500|오뚜기,비비고 왕교자 1kg|12900|CJ비비고,풀무원 두부 찌개용|2500|풀무원,서울우유 1L|2800|서울우유,하겐다즈 바닐라 파인트|9900|Haagen-Dazs,스타벅스 원두 하우스블렌드|15900|Starbucks,곰곰 무항생제 달걀 30구|8900|곰곰,제주삼다수 2L 6본|5400|삼다수,종가집 포기김치 3kg|22900|종가집,참이슬 후레쉬 360ml 20본|28900|하이트진로,카스 프레시 500ml 12캔|16900|OB맥주,동원 참치캔 150g 5입|9900|동원,오리온 초코파이 12입|4900|오리온"
PRODUCTS[3]="설화수 자음생크림|179000|설화수,에스티로더 어드밴스 나이트 리페어|135000|Estee Lauder,라네즈 워터 슬리핑 마스크|32000|라네즈,이니스프리 그린티 세럼|25000|이니스프리,헤라 블랙 쿠션|55000|HERA,SK-II 피테라 에센스|189000|SK-II,닥터자르트 시카페어 크림|48000|Dr.Jart+,아모레 비오템 옴므 세트|65000|Biotherm,클리오 킬커버 파운데이션|28000|CLIO,VT 리들샷 100 에센스|23000|VT,마녀공장 퓨어 클렌징 오일|18000|마녀공장,토니모리 달팽이 크림|22000|TONYMOLY,미샤 타임레볼루션 앰플|35000|MISSHA,코스알엑스 스네일 에센스|19000|COSRX,에뛰드 플레이컬러 아이즈|24000|ETUDE"
PRODUCTS[4]="LG 스탠바이미 Go|1090000|LG전자,삼성 비스포크 냉장고 4도어|2890000|삼성전자,LG 트롬 워시타워|2490000|LG전자,삼성 비스포크 에어컨|1990000|삼성전자,LG 퓨리케어 공기청정기|699000|LG전자,다이슨 V15 디텍트|1190000|Dyson,쿠쿠 IH 전기밥솥|399000|쿠쿠,필립스 에어프라이어 XXL|329000|Philips,삼성 비스포크 식기세척기|1290000|삼성전자,LG 코드제로 A9S|899000|LG전자,위닉스 제습기 16L|389000|위닉스,브레빌 바리스타 익스프레스|799000|Breville,발뮤다 더 토스터|299000|BALMUDA,일렉트로룩스 로봇청소기|599000|Electrolux,LG 디오스 오브제컬렉션 전자레인지|399000|LG전자"
PRODUCTS[5]="나이키 드라이핏 반팔 티|45000|Nike,요넥스 배드민턴 라켓 아스트록스|289000|YONEX,윌슨 프로스태프 테니스 라켓|359000|Wilson,가민 포러너 265|529000|Garmin,블랙야크 등산화 트레킹|189000|BLACKYAK,데카트론 요가매트 8mm|29900|Decathlon,나이키 줌 페가수스 41|159000|Nike,아디다스 프레데터 축구화|199000|Adidas,미즈노 웨이브라이더 28|179000|MIZUNO,언더아머 퍼포먼스 폴로|79000|Under Armour,살로몬 스피드크로스 6|189000|Salomon,핑 G430 드라이버|699000|PING,타이틀리스트 프로V1 골프공|69000|Titleist,코베아 캠핑 텐트 4인용|459000|KOVEA,스노우피크 티타늄 머그|59000|Snow Peak"
PRODUCTS[6]="원씽 복잡한 세상을 이기는 단순함의 힘|14400|비즈니스북스,아토믹 해빗|16200|비즈니스북스,역행자|17100|웅진지식하우스,불편한 편의점 3|14400|나무옆의자,트렌드 코리아 2026|19800|미래의창,세이노의 가르침|6480|데이원,데일 카네기 인간관계론|16200|현대지성,이것이 자바다 개정판|36000|한빛미디어,클린 코드|33000|인사이트,파친코 양장본|18900|문학사상,해리포터 시리즈 전집|108000|문학수첩,Do it 점프 투 파이썬|18800|이지스퍼블리싱,코스모스 칼 세이건|22500|사이언스북스,지구끝의 온실|14400|자이언트북스,나미야 잡화점의 기적|14400|현대문학"
PRODUCTS[7]="로얄캐닌 인도어 고양이사료 4kg|49000|Royal Canin,오리젠 오리지널 독 6kg|89000|ORIJEN,퓨리나 프로플랜 연어 7kg|55000|Purina,캣타워 대형 나무 놀이터|89000|펫트리,강아지 자동급식기 5L|59000|페코,고양이 화장실 후드형|45000|캣아이디어,반려동물 이동장 항공형|35000|리치엘,강아지 하네스 세트|25000|줄리어스K9,고양이 스크래처 골판지|12000|네이처펫,반려동물 자동 물분수|39000|카타잇,강아지 치석제거 덴탈껌|15000|그리니스,고양이 츄르 참치 20개입|12000|이나바,반려동물 GPS 트래커|99000|핏빗펫,강아지 방석 메모리폼 L|49000|보듬,고양이 장난감 깃털 낚시대|8000|캣폴"
PRODUCTS[8]="이케아 칼락스 선반유닛|79900|IKEA,한샘 시스템 옷장 3.2m|2990000|한샘,일룸 쿠시노 소파 3인|1890000|일룸,시디즈 T80 사무용 의자|599000|SIDIZ,에이스침대 하이브리드 퀸|3490000|에이스침대,리바트 원목 식탁세트 6인|1290000|리바트,이케아 말름 서랍장 6칸|229000|IKEA,데스커 모션데스크 1400|799000|DESKER,한샘 수납 책장 5단|349000|한샘,이케아 포엥 암체어|199000|IKEA,일룸 키즈 성장 책상|890000|일룸,쁘띠메종 LED 거울|159000|쁘띠메종,니토리 접이식 매트리스|199000|NITORI,코지 패브릭 1인 소파|299000|COZY,무인양품 스택식 선반|129000|MUJI"
PRODUCTS[9]="싸이벡스 프리암 유모차|1590000|Cybex,스토케 트립트랩 하이체어|449000|Stokke,하기스 맥스드라이 기저귀 L|35900|하기스,보령 앱솔루트 분유 3단계|29900|보령,닥터브라운 젖병 세트|39000|Dr Browns,레고 듀플로 대형 놀이상자|69900|LEGO,피셔프라이스 아기 체육관|55000|Fisher-Price,에르고베이비 옴니 360|289000|Ergobaby,베베숲 물티슈 80매 10팩|15900|베베숲,맥시코시 카시트 투비스|490000|Maxi-Cosi,아가방 신생아 내의 세트|32000|아가방,브이텍 학습 테이블|59000|VTech,콤비 유모차 스고칼|890000|Combi,포디언 아기침대 범퍼세트|129000|포디언,누크 이유식 조리기|89000|NUK"

BULK_FILE=$(mktemp)
IDX=1

for cat_idx in $(seq 0 9); do
  IFS=',' read -ra ITEMS <<< "${PRODUCTS[$cat_idx]}"
  for item in "${ITEMS[@]}"; do
    IFS='|' read -r pname pprice pbrand <<< "$item"
    pid="PROD-$(printf '%03d' $IDX)"
    rating=$(echo "scale=1; 3.5 + ($RANDOM % 15) / 10" | bc)
    reviews=$(( RANDOM % 500 + 10 ))
    discount_vals=(0 0 0 5 10 15 20 25 30)
    discount=${discount_vals[$(( RANDOM % 9 ))]}
    if [ "$discount" -gt 0 ]; then
      sale_price=$(( pprice * (100 - discount) / 100 ))
    else
      sale_price=0
    fi
    stock=$(( RANDOM % 500 + 5 ))
    origins=("한국" "미국" "일본" "독일" "중국" "프랑스")
    origin=${origins[$(( RANDOM % 6 ))]}

    # Bulk API action line
    echo "{\"index\":{\"_index\":\"products\",\"_id\":\"${pid}\"}}" >> "$BULK_FILE"
    # Document
    cat >> "$BULK_FILE" <<ENDJSON
{"productId":"${pid}","name":"${pname}","brand":"${pbrand}","category":"${CAT_SLUGS[$cat_idx]}","categoryName":"${CATEGORIES[$cat_idx]}","description":"${pbrand}의 ${pname}입니다. 최고의 품질과 디자인을 자랑합니다.","price":${pprice},"salePrice":${sale_price},"discount":${discount},"rating":${rating},"reviewCount":${reviews},"tags":["${CAT_SLUGS[$cat_idx]}","인기상품"],"status":"active","stock":${stock},"origin":"${origin}","createdAt":"$(date -u -d "-$(( RANDOM % 365 )) days" +%Y-%m-%dT%H:%M:%SZ 2>/dev/null || date -u +%Y-%m-%dT%H:%M:%SZ)"}
ENDJSON
    IDX=$(( IDX + 1 ))
  done
done

echo "Bulk indexing ${IDX} products..."
RESPONSE=$($CURL -X POST "${OS_ENDPOINT}/_bulk" -H 'Content-Type: application/x-ndjson' --data-binary "@${BULK_FILE}")
ERRORS=$(echo "$RESPONSE" | python3 -c "import sys,json; d=json.load(sys.stdin); print(d.get('errors',True))" 2>/dev/null || echo "unknown")

if [ "$ERRORS" = "False" ]; then
  echo "Bulk indexing complete: $(( IDX - 1 )) products indexed successfully"
else
  echo "Bulk indexing completed with some errors. Check response."
  echo "$RESPONSE" | python3 -c "
import sys, json
d = json.load(sys.stdin)
errs = [i for i in d.get('items',[]) if 'error' in i.get('index',{})]
print(f'Errors: {len(errs)}')
for e in errs[:5]:
    print(f'  {e[\"index\"][\"_id\"]}: {e[\"index\"][\"error\"][\"reason\"]}')
" 2>/dev/null || true
fi

rm -f "$BULK_FILE"

# ── Create notification index ───────────────────────────────────────────────
echo ""
echo "Creating notification-logs index..."
$CURL -X DELETE "${OS_ENDPOINT}/notification-logs" 2>/dev/null || true
$CURL -X PUT "${OS_ENDPOINT}/notification-logs" -H 'Content-Type: application/json' -d '{
  "settings": { "number_of_shards": 2, "number_of_replicas": 1 },
  "mappings": {
    "properties": {
      "userId":    { "type": "keyword" },
      "type":      { "type": "keyword" },
      "channel":   { "type": "keyword" },
      "title":     { "type": "text", "analyzer": "korean" },
      "status":    { "type": "keyword" },
      "sentAt":    { "type": "date" },
      "readAt":    { "type": "date" }
    }
  }
}'
echo ""

# ── Create order-events index ───────────────────────────────────────────────
echo "Creating order-events index..."
$CURL -X DELETE "${OS_ENDPOINT}/order-events" 2>/dev/null || true
$CURL -X PUT "${OS_ENDPOINT}/order-events" -H 'Content-Type: application/json' -d '{
  "settings": { "number_of_shards": 3, "number_of_replicas": 1 },
  "mappings": {
    "properties": {
      "orderId":   { "type": "keyword" },
      "userId":    { "type": "keyword" },
      "eventType": { "type": "keyword" },
      "status":    { "type": "keyword" },
      "amount":    { "type": "long" },
      "timestamp": { "type": "date" }
    }
  }
}'
echo ""

# ── Verify ──────────────────────────────────────────────────────────────────
echo ""
echo "=== Verification ==="
echo -n "Products count: "
$CURL "${OS_ENDPOINT}/products/_count" | python3 -c "import sys,json; print(json.load(sys.stdin).get('count',0))" 2>/dev/null || echo "?"

echo -n "Sample search for '삼성': "
$CURL -X POST "${OS_ENDPOINT}/products/_search" -H 'Content-Type: application/json' -d '{
  "query": { "match": { "name": "삼성" } },
  "size": 0
}' | python3 -c "import sys,json; print(json.load(sys.stdin).get('hits',{}).get('total',{}).get('value',0), 'hits')" 2>/dev/null || echo "?"

echo ""
echo "OpenSearch seed complete!"

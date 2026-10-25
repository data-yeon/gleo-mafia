"""진술을 한국어 문장으로 바꾼다.

fact(): 정리 화면용 중립 문장
speak(): 제보자 대사 템플릿. 제품에서는 LLM이 이 내용을 캐릭터 말투로 바꾸고, 실패하면 이 템플릿을 쓴다.
"""
from __future__ import annotations

from .board import Board
from .model import Clue, ClueType, Role, indices_of

CIRCLED = "①②③④⑤⑥⑦⑧⑨⑩⑪⑫"


def pid(i: int) -> str:
    return CIRCLED[i]


def _batchim(word: str) -> bool:
    ch = word.strip()[-1]
    if "가" <= ch <= "힣":
        return (ord(ch) - 0xAC00) % 28 != 0
    return ch in "013678"            # 숫자로 끝나면 읽는 소리 기준


def josa(word: str, pair: str) -> str:
    """pair 예: '은는', '이가', '과와', '을를'."""
    return word + (pair[0] if _batchim(word) else pair[1])


def euro(word: str) -> str:
    """'(으)로' 붙이기. ㄹ받침은 '로'."""
    ch = word.strip()[-1]
    if "가" <= ch <= "힣":
        jong = (ord(ch) - 0xAC00) % 28
        return word + ("으로" if jong not in (0, 8) else "로")
    return word + "로"


def was(word: str) -> str:
    """'~이었어요/였어요'."""
    return word + ("이었어요" if _batchim(word) else "였어요")


def irago(word: str) -> str:
    """'~(이)라고'."""
    return word + ("이라고" if _batchim(word) else "라고")


def num(i: int) -> str:
    """음성용 장소 번호. '3번'"""
    return f"{i + 1}번"


def place_label(board: Board, i: int) -> str:
    return f"{pid(i)} {board.places[i].name}"


def members(region: int) -> str:
    idx = indices_of(region)
    return "".join(pid(i) for i in idx) if idx else "없음"


def km(radius_m: int) -> str:
    return f"{radius_m / 1000:g}km"


def count_word(n: int) -> str:
    return {0: "한 곳도 없어", 1: "딱 한 곳 있어", 2: "두 곳 있어", 3: "세 곳 있어"}.get(n, f"{n}곳 있어")


def fact(clue: Clue, board: Board) -> str:
    t = clue.type
    if t is ClueType.RADIUS:
        return (f"{place_label(board, clue.center)}에서 {km(clue.radius)} 안"
                f"({members(clue.region)})에 숨은 곳 {clue.count}곳")
    if t is ClueType.SPAN:
        return f"경로상 {pid(clue.lo)}~{pid(clue.hi)} 구간({members(clue.region)})에 숨은 곳 {clue.count}곳"
    if t is ClueType.SIDE:
        return f"경로 {clue.side}({members(clue.region)})에 숨은 곳 {clue.count}곳"
    if t is ClueType.NEIGHBOR:
        return (f"{pid(clue.center)} 앞뒤로 지나가는 두 곳"
                f"({members(clue.region)}) 중 숨은 곳 {clue.count}곳")
    if t is ClueType.KIND:
        return f"{clue.kind}({members(clue.region)}) 중 숨은 곳 {clue.count}곳"
    if t is ClueType.ROAD:
        return f"길가 장소({members(clue.region)}) 중 숨은 곳 {clue.count}곳"
    if t is ClueType.VOUCH:
        target = place_label(board, clue.target)
        return f"{josa(target, '은는')} 수상하다" if clue.claim else f"{josa(target, '은는')} 깨끗하다"
    target = place_label(board, clue.target)
    return (f"{target}의 제보자는 신분을 속이고 있다" if clue.claim
            else f"{target}의 제보자는 겉과 속이 같다")


def speak(clue: Clue, board: Board, shown: Role | None) -> str:
    """shown=None이면 익명 제보."""
    t = clue.type
    n = clue.count
    if shown is None:
        return f"(변조된 목소리) 이름은 못 밝혀요. 들은 얘긴데… {fact(clue, board)}이래요."
    if shown is Role.GOSSIP:
        return f"아이고, 내가 다 봤다니까! {fact(clue, board)}이야, 틀림없어!"
    if t is ClueType.RADIUS:
        return f"여기서 장사만 30년이야. {km(clue.radius)} 안에 수상한 데가 {count_word(n)}."
    if t is ClueType.ROAD:
        return f"손님 태우고 이 길 수십 번 다녔죠. 바로 길가에 있는 곳들 중엔 수상한 데가 {count_word(n)}요."
    if t is ClueType.SPAN:
        return (f"손님 태우고 이 길 수십 번 다녔죠. {pid(clue.lo)}{board.places[clue.lo].name}부터 "
                f"{pid(clue.hi)}{board.places[clue.hi].name}까지 가는 길에 수상한 데가 {count_word(n)}요.")
    if t is ClueType.SIDE:
        return f"드론으로 찍어 보니까요, 가시는 길 {clue.side}엔 수상한 데가 {count_word(n)}요."
    if t is ClueType.NEIGHBOR:
        a, b = indices_of(clue.region)
        return (f"이 동네는 내가 다 알지. 이 앞뒤로 지나가는 {pid(a)}{board.places[a].name}, "
                f"{pid(b)}{board.places[b].name} 중에 수상한 데가 {count_word(n)}.")
    if t is ClueType.KIND:
        return f"배달 다니면서 보면요, {clue.kind} 쪽엔 수상한 데가 {count_word(n)}요."
    target = place_label(board, clue.target)
    if t is ClueType.VOUCH:
        if clue.claim:
            return f"{target} 쪽이 수상해요. 밤마다 사람들이 들락거려요."
        return f"{target} 쪽은 제가 보증해요. 깨끗해요."
    if clue.claim:
        return f"{target}에 있는 사람, 신분을 속이고 있어요. 제가 확인했습니다."
    return f"{target}에 있는 사람은 겉과 속이 같아요. 믿으셔도 됩니다."

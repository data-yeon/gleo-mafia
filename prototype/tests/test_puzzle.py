"""퍼즐 엔진 기본 검증.

python3 -m unittest discover -s tests   (prototype 폴더에서 실행)
"""
import random
import sys
import unittest
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))

from puzzle.generator import generate_case  # noqa: E402
from puzzle.model import HONEST_ROLES, Role, popcount  # noqa: E402
from puzzle.solver import CaseAnalyzer  # noqa: E402

PRESET_KEYS = ("easy", "normal", "hard", "phishing")


class SolverSoundness(unittest.TestCase):
    def test_truth_always_survives(self):
        """어떤 관찰 조합에서도 실제 정답은 후보에서 빠지면 안 된다."""
        rng = random.Random(7)
        for key in PRESET_KEYS:
            for seed in range(6):
                case = generate_case(key, seed)
                an = CaseAnalyzer(case)
                roadside = [p.index for p in case.file.board.places if p.roadside]
                for _ in range(12):
                    k = rng.randint(1, case.file.board.n)
                    subset = rng.sample(range(case.file.board.n), k)
                    observed = {i: (i in roadside and rng.random() < 0.5) for i in subset}
                    revealed = rng.sample(range(case.file.board.n), rng.randint(0, 3))
                    res = an.solve(observed, revealed)
                    self.assertIn(case.truth.hidden, res, f"{key} seed={seed} obs={observed}")

    def test_unique_with_all(self):
        for key in PRESET_KEYS:
            for seed in range(6):
                self.assertTrue(CaseAnalyzer(generate_case(key, seed)).unique_with_all())


class GeneratorRules(unittest.TestCase):
    def test_composition_and_disguise(self):
        for key in PRESET_KEYS:
            for seed in range(10):
                case = generate_case(key, seed)
                t, cf = case.truth, case.file
                self.assertEqual(popcount(t.hidden), cf.preset.n_evil)
                honest = [r for r in t.roles if r in HONEST_ROLES]
                self.assertEqual(len(honest), len(set(honest)), "정직 직업은 중복 없음")
                self.assertEqual(len(honest), cf.n_honest)
                for r, s in zip(t.roles, t.shown):
                    if r in HONEST_ROLES or r is Role.GOSSIP:
                        self.assertIs(r, s)
                    else:
                        self.assertIn(s, HONEST_ROLES)
                        if r is not Role.IMPOSTER:
                            self.assertIsNot(s, Role.COP, "사칭범 말고는 경관으로 위장하지 않는다")
                        if r in (Role.THUG, Role.IMPOSTER):
                            self.assertIn(s, honest, "행동대원·사칭범은 판에 있는 직업으로 위장")
                        else:
                            self.assertNotIn(s, honest, "협박꾼·보스·취객은 판에 없는 직업으로 위장")
                if cf.preset.force_cop_claim:
                    imp = [i for i, r in enumerate(t.roles) if r is Role.IMPOSTER]
                    self.assertTrue(all(t.shown[i] is Role.COP for i in imp), "데모 사칭범은 경관 행세")
                self.assertEqual(len(cf.anonymous), cf.preset.anonymous)
                sides = {p.side for p in cf.board.places}
                self.assertEqual(sides, {"왼편", "오른편"})
                order = [p.route_pos for p in cf.board.places]
                self.assertEqual(order, sorted(order), "번호 = 지나가는 순서")

    def test_statement_truthfulness(self):
        for key in PRESET_KEYS:
            for seed in range(10):
                case = generate_case(key, seed)
                t = case.truth
                for i, (r, clue) in enumerate(zip(t.roles, t.clues)):
                    holds = clue.holds(t.hidden, t.disguised)
                    if r is Role.GOSSIP:
                        self.assertTrue(clue.holds(t.hidden, t.disguised, offset=1))
                    elif r in HONEST_ROLES and i not in t.tainted:
                        self.assertTrue(holds)
                    else:
                        self.assertFalse(holds)
                for i, clue in t.stakeout_clues.items():
                    self.assertTrue(clue.holds(t.hidden, t.disguised), "잠복 진술은 항상 참")


class GameRules(unittest.TestCase):
    def test_stakeout_window_and_expiry(self):
        from puzzle.game import Game
        from puzzle.rules import STAKEOUT_LOOKAHEAD, STAKEOUT_PASS
        for seed in range(10):
            g = Game(generate_case("normal", seed))
            road = [p for p in g.board.places if p.roadside]
            for p in road:
                g.clock = p.route_pos - STAKEOUT_LOOKAHEAD - 0.01
                self.assertNotIn(p.index, g.stakeout_available(), "다가가기 전에는 불가")
                g.clock = p.route_pos
                self.assertIn(p.index, g.stakeout_available(), "지나가는 중에는 가능")
                if p.route_pos + STAKEOUT_PASS + 0.01 >= 1.0:
                    continue                      # 목적지 바로 앞 장소는 '지나친 뒤'가 없다
                g.clock = p.route_pos + STAKEOUT_PASS + 0.01
                self.assertNotIn(p.index, g.stakeout_available(), "지나치면 불가")
                self.assertIn(p.index, g.stakeout_missed())

    def test_calls_advance_clock_to_final_phase(self):
        from puzzle.game import Game
        from puzzle.rules import FINAL_PHASE_START
        g = Game(generate_case("normal", 1))
        for i in range(g.budget):
            g.investigate(i)
        self.assertTrue(g.final_phase)
        self.assertAlmostEqual(g.progress, FINAL_PHASE_START)
        self.assertEqual(g.final_raids_left, g.n_evil + 1)


class CityBoard(unittest.TestCase):
    def test_astar_matches_dijkstra_and_route_is_connected(self):
        import heapq
        from puzzle.city import (_turn_deg, astar, edge_seconds, make_city, route_through,
                                 turn_penalty)

        def dijkstra(c, s, g):
            dist = {(s, -1): 0.0}
            heap = [(0.0, 0, (s, -1))]
            cnt = 0
            closed = set()
            while heap:
                d, _, st = heapq.heappop(heap)
                if st in closed:
                    continue
                closed.add(st)
                n, p = st
                if n == g:
                    return d
                for e in c.adj[n]:
                    nx = c.other(e, n)
                    if nx == p:
                        continue
                    cost = d + edge_seconds(c.edges[e])
                    if p >= 0:
                        cost += turn_penalty(_turn_deg(c.nodes[p], c.nodes[n], c.nodes[nx]))
                    if cost < dist.get((nx, n), 1e18):
                        dist[(nx, n)] = cost
                        cnt += 1
                        heapq.heappush(heap, (cost, cnt, (nx, n)))

        rng = random.Random(3)
        c = make_city(rng)
        for _ in range(15):
            a, b = rng.randrange(len(c.nodes)), rng.randrange(len(c.nodes))
            if a == b:
                continue
            path, cost, _ = astar(c, a, b)
            self.assertAlmostEqual(cost, dijkstra(c, a, b), places=6, msg="A*는 최적")
            for u, v in zip(path, path[1:]):
                self.assertNotEqual(c.edge_between(u, v), -1, "경로는 도로를 따라간다")
            for k in range(1, len(path) - 1):
                self.assertNotEqual(path[k - 1], path[k + 1], "유턴 없음")
        wp = rng.randrange(len(c.nodes))
        path, _ = route_through(c, [0, wp, len(c.nodes) - 1])
        self.assertIn(wp, path, "경유지를 지난다")

    def test_city_board(self):
        for key in ("normal", "phishing"):
            for seed in range(5):
                case = generate_case(key, seed)
                b = case.file.board
                plan = b.world["plan"]
                self.assertTrue(8500 <= plan["length"] <= 12500)
                self.assertGreaterEqual(len(plan["tunnels"]), 1)
                self.assertTrue(2 <= len(plan["stops"]) <= 3)
                self.assertTrue(any(m["icon"].startswith("turn") for m in plan["maneuvers"]), "회전 안내")
                self.assertEqual(len(b.places), 9)
                self.assertIn(sum(1 for p in b.places if p.roadside), (2, 3))
                for p in b.places:
                    if p.roadside:
                        self.assertLessEqual(p.route_dist, 80.0, "길가 장소는 도로에 붙어 있다")
                    else:
                        self.assertGreaterEqual(p.route_dist, 400.0)
                self.assertEqual(len(case.truth.stakeout_clues), 9, "모든 장소에 잠복 진술")


if __name__ == "__main__":
    unittest.main()

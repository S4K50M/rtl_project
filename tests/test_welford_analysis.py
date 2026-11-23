"""Offline Welford edge cases; no simulator required."""
import unittest
from analysis.welford_analysis import analyze_samples


class OfflineWelfordTests(unittest.TestCase):
    def test_known_population_statistics(self):
        trace, result = analyze_samples([2, 4, 4, 4, 5, 5, 7, 9])
        self.assertAlmostEqual(result['reference_mean'], 5)
        self.assertAlmostEqual(result['reference_population_variance'], 4)
        self.assertAlmostEqual(trace[-1]['welford_population_variance'], 4)
        self.assertLess(abs(result['final_fixed_mean_error']), 0.001)
        self.assertLess(abs(result['final_fixed_variance_error']), 0.001)

    def test_signed_truncation_and_constant_input(self):
        trace, _ = analyze_samples([2, 0, 0])
        self.assertEqual(trace[-1]['mean_q16'], 43691)
        _, result = analyze_samples([17]*100)
        self.assertEqual(result['fixed_mean'], 17)
        self.assertEqual(result['variance_q16'], 0)

    def test_input_clamp_variance_saturation_and_count_limit(self):
        trace, result = analyze_samples([0, 50000, 123], max_samples=2)
        self.assertEqual(trace[1]['clamped_latency_cycles'], 32767)
        self.assertEqual(trace[1]['variance_q16'], 0xffffffff)
        self.assertEqual(trace[2]['count'], 2)
        self.assertEqual(trace[2]['mean_q16'], trace[1]['mean_q16'])
        self.assertEqual(result['ignored_after_count_limit'], 1)
        self.assertEqual(result['clamped_accepted_samples'], 1)

    def test_invalid_input(self):
        for samples in ([], [-1], [1 << 32]):
            with self.assertRaises(ValueError):
                analyze_samples(samples)


if __name__ == '__main__':
    unittest.main()

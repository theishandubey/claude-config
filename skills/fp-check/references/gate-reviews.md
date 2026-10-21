# Gate Reviews and Verdicts

Before reporting ANY bug as a vulnerability, all six gate reviews must pass. Evaluate them after all checklist steps are complete:

| Gate | Criterion | Pass | Fail |
|------|-----------|------|------|
| **1. Process** | All phases completed with documented evidence | Evidence exists for every phase | Phases lack concrete evidence |
| **2. Reachability** | Attacker can reach and control data at the vulnerability | Clear evidence of attacker-controlled path, confirmed by the attack path | Cannot demonstrate attacker control or reachability |
| **3. Real Impact** | Exploitation leads to RCE, privesc, or info disclosure | Direct impact with concrete scenarios | Only operational robustness issue |
| **4. Attack Path** | The attack-path description demonstrates the path | Shows attacker control, trigger condition, and impact | Fails to show the path or the impact |
| **5. Math Bounds** | Mathematical analysis confirms vulnerable condition is possible | Algebraic proof shows condition is possible | Math proves validation prevents it |
| **6. Environment** | No environmental protections entirely prevent exploitation | Protections do not eliminate vulnerability | Environmental protections block it entirely |

## Verdict Format

- **TRUE POSITIVE**: All gate reviews pass → `BUG #N TRUE POSITIVE - [brief vulnerability description]`
- **FALSE POSITIVE**: Any gate review fails with evidence → `BUG #N FALSE POSITIVE - [brief reason for rejection]`
- **UNRESOLVED**: A gate cannot be settled with the evidence at hand → `BUG #N UNRESOLVED - [what is missing]`

If any phase fails verification, document the failure with evidence and continue all remaining phases. Issue the FALSE POSITIVE verdict only after all phases are complete.

## Example Verdict

```
BUG #3 FALSE POSITIVE - Integer underflow in packet_handler.c:142
  Gate 5 (Math Bounds) FAIL: validation at line 98 ensures packet_size >= 16,
  making (packet_size - header_size) >= 8. Underflow is mathematically impossible.
```

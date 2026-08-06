import Foundation

// MARK: - VPNClassifier

precondition(VPNClassifier.isVPN(interface: "utun4", ignoring: []) == true,
             "utun is a tunnel interface")
precondition(VPNClassifier.isVPN(interface: "ipsec0", ignoring: []) == true,
             "ipsec is a tunnel interface")
precondition(VPNClassifier.isVPN(interface: "en0", ignoring: []) == false,
             "ethernet is not a tunnel")
precondition(VPNClassifier.isVPN(interface: "", ignoring: []) == false,
             "empty interface means unknown, not tunneled")
precondition(VPNClassifier.isVPN(interface: "  utun4 ", ignoring: []) == true,
             "surrounding whitespace is trimmed")
precondition(VPNClassifier.isVPN(interface: "utun4", ignoring: ["utun4"]) == false,
             "an ignored interface is not reported as a tunnel")
precondition(VPNClassifier.isVPN(interface: "utun10", ignoring: ["utun1"]) == true,
             "the ignore list matches whole names, never prefixes")

precondition(VPNClassifier.parseIgnoreList("utun0, utun1") == ["utun0", "utun1"],
             "comma separated")
precondition(VPNClassifier.parseIgnoreList("utun0 utun1") == ["utun0", "utun1"],
             "space separated")
precondition(VPNClassifier.parseIgnoreList("") == [],
             "empty string yields an empty set")
precondition(VPNClassifier.parseIgnoreList("  ,  ") == [],
             "separators only yields an empty set")

print("self-checks passed")

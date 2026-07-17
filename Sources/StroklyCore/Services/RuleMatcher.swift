import Foundation

public enum RuleMatcher {
    public static let noisePenaltyPerReset: Double = 0.02

    public struct TemplateMatch: Equatable {
        public var rule: GestureRule
        public var score: Double
    }

    public static func match(
        signature: GestureSignature,
        triggerButton: TriggerButton = .rightMouse,
        activeModifiers: [KeyboardModifier] = [],
        bundleIdentifier: String?,
        rules: [GestureRule]
    ) -> GestureRule? {
        let eligibleRules = rules.filter { rule in
            rule.isEnabled &&
                rule.triggerButton == triggerButton &&
                rule.signature == signature &&
                matchesModifiers(required: rule.modifierRequirements, active: activeModifiers)
        }

        if let bundleIdentifier,
           let scopedRule = eligibleRules.first(where: { rule in
               rule.scope.kind == .application &&
                   rule.scope.bundleIdentifier == bundleIdentifier
           }) {
            return scopedRule
        }

        return eligibleRules.first { $0.scope.kind == .global }
    }

    public static func match(
        template: GestureTemplate,
        signature: GestureSignature,
        triggerButton: TriggerButton = .rightMouse,
        activeModifiers: [KeyboardModifier] = [],
        bundleIdentifier: String?,
        noiseCount: Int = 0,
        rules: [GestureRule]
    ) -> GestureRule? {
        matchWithScore(
            template: template,
            signature: signature,
            triggerButton: triggerButton,
            activeModifiers: activeModifiers,
            bundleIdentifier: bundleIdentifier,
            noiseCount: noiseCount,
            rules: rules
        )?.rule
    }

    public static func matchWithScore(
        template: GestureTemplate,
        signature: GestureSignature,
        triggerButton: TriggerButton = .rightMouse,
        activeModifiers: [KeyboardModifier] = [],
        bundleIdentifier: String?,
        noiseCount: Int = 0,
        rules: [GestureRule]
    ) -> TemplateMatch? {
        let eligibleRules = rules.filter { rule in
            rule.isEnabled &&
                rule.triggerButton == triggerButton &&
                !rule.template.isEmpty &&
                matchesModifiers(required: rule.modifierRequirements, active: activeModifiers)
        }

        let appRules = eligibleRules.filter { rule in
            guard let bundleIdentifier else { return false }
            return rule.scope.kind == .application &&
                rule.scope.bundleIdentifier == bundleIdentifier
        }

        // 1. App-scoped: normal tolerance match
        if let best = scoredMatches(template: template, signature: signature, noiseCount: noiseCount, toleranceScale: 1.0, rules: appRules).first {
            return best
        }

        // 2. App-scoped: relaxed tolerance for exact signature match (prevent global from stealing)
        if let best = scoredMatches(template: template, signature: signature, noiseCount: noiseCount, toleranceScale: 1.5, requireExactSignature: true, rules: appRules).first {
            return best
        }

        // 3. Global: normal tolerance match
        return scoredMatches(
            template: template,
            signature: signature,
            noiseCount: noiseCount,
            toleranceScale: 1.0,
            rules: eligibleRules.filter { $0.scope.kind == .global }
        ).first
    }

    public static func detectConflicts(
        template: GestureTemplate,
        triggerButton: TriggerButton = .rightMouse,
        scope: RuleScope = .global,
        excludeRuleID: UUID? = nil,
        rules: [GestureRule]
    ) -> [GestureRule] {
        let eligible = rules.filter { rule in
            rule.isEnabled &&
                rule.triggerButton == triggerButton &&
                !rule.template.isEmpty &&
                rule.id != excludeRuleID &&
                scopesOverlap(scope, rule.scope)
        }
        return eligible.filter { rule in
            GestureTemplateMatcher.distance(template, rule.template) < rule.matchTolerance * 0.7
        }
    }

    public static func scopesOverlap(_ a: RuleScope, _ b: RuleScope) -> Bool {
        switch (a.kind, b.kind) {
        case (.global, _), (_, .global):
            return true
        case (.application, .application):
            return a.bundleIdentifier == b.bundleIdentifier
        }
    }

    private static func matchesModifiers(required: [KeyboardModifier], active: [KeyboardModifier]) -> Bool {
        let requiredSet = Set(required)
        let activeSet = Set(active)
        return requiredSet.isSubset(of: activeSet)
    }

    private static func scoredMatches(
        template: GestureTemplate,
        signature: GestureSignature,
        noiseCount: Int,
        toleranceScale: Double = 1.0,
        requireExactSignature: Bool = false,
        rules: [GestureRule]
    ) -> [TemplateMatch] {
        rules.compactMap { rule -> TemplateMatch? in
            if requireExactSignature && rule.signature != signature {
                return nil
            }
            let rawDistance = GestureTemplateMatcher.distance(template, rule.template)
            let adjustedScore = min(rawDistance + Double(noiseCount) * noisePenaltyPerReset, 3.0)
            guard adjustedScore <= rule.matchTolerance * toleranceScale else {
                return nil
            }
            return TemplateMatch(rule: rule, score: adjustedScore)
        }
        .sorted { left, right in
            left.score < right.score
        }
    }
}

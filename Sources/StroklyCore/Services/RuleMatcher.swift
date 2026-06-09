import Foundation

public enum RuleMatcher {
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
        rules: [GestureRule]
    ) -> GestureRule? {
        matchWithScore(
            template: template,
            signature: signature,
            triggerButton: triggerButton,
            activeModifiers: activeModifiers,
            bundleIdentifier: bundleIdentifier,
            rules: rules
        )?.rule
    }

    public static func matchWithScore(
        template: GestureTemplate,
        signature: GestureSignature,
        triggerButton: TriggerButton = .rightMouse,
        activeModifiers: [KeyboardModifier] = [],
        bundleIdentifier: String?,
        rules: [GestureRule]
    ) -> TemplateMatch? {
        let eligibleRules = rules.filter { rule in
            rule.isEnabled &&
                rule.triggerButton == triggerButton &&
                !rule.template.isEmpty &&
                matchesModifiers(required: rule.modifierRequirements, active: activeModifiers)
        }

        let appMatches = scoredMatches(
            template: template,
            rules: eligibleRules.filter { rule in
                guard let bundleIdentifier else {
                    return false
                }
                return rule.scope.kind == .application &&
                    rule.scope.bundleIdentifier == bundleIdentifier
            }
        )
        if let best = appMatches.first {
            return best
        }

        return scoredMatches(
            template: template,
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

    private static func scoredMatches(template: GestureTemplate, rules: [GestureRule]) -> [TemplateMatch] {
        rules.compactMap { rule -> TemplateMatch? in
            let score = GestureTemplateMatcher.distance(template, rule.template)
            guard score <= rule.matchTolerance else {
                return nil
            }
            return TemplateMatch(rule: rule, score: score)
        }
        .sorted { left, right in
            left.score < right.score
        }
    }
}

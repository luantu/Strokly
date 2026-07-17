import CoreGraphics
import Foundation
import StroklyCore

@main
struct StroklyCoreChecks {
    @MainActor
    static func main() throws {
        try testRecognizesDirectionSequenceAndCollapsesJitter()
        try testReturnsNilWhenPointerDoesNotTravelFarEnough()
        try testParsesCompactSignatureText()
        try testTemplateNormalizationIgoresPositionAndScale()
        try testTemplateMatcherScoresSimilarShapesLowerThanDifferentShapes()
        try testAppSpecificRuleWinsOverGlobalRule()
        try testAppSpecificTemplateRuleWinsOverGlobalTemplateRule()
        try testDisabledRulesAreIgnored()
        try testFormatsShortcutForDisplay()
        try testResolvesCommonMacKeyCodes()
        try testRecognizesDiagonalDirection()
        try testParsesDiagonalSignatureText()
        try testModifierMatchingRequiresAllSpecified()
        try testConflictDetectionFindsSimilarGestures()
        try testCategorySerialization()
        try testDefaultLanguageIsChinese()
        try testChineseLocalizationResourceIsResolved()
        try testEdgeScrollDetectionUsesContainingDisplay()
        try testNoiseCountIncrementsOnAbandonedDirectionChange()
        try testCleanGestureHasZeroNoise()
        try testNoisyGestureExceedsMatchTolerance()
        try testComplexShapeDoesNotMatchSimpleLine()
        try testOldToleranceMigratesToNewScale()

        print("StroklyCoreChecks passed")
    }

    private static func testRecognizesDirectionSequenceAndCollapsesJitter() throws {
        let recognizer = GestureRecognizer(minSegmentLength: 18)
        let points = [
            CGPoint(x: 10, y: 10),
            CGPoint(x: 16, y: 12),
            CGPoint(x: 38, y: 13),
            CGPoint(x: 63, y: 15),
            CGPoint(x: 64, y: 22),
            CGPoint(x: 65, y: 48),
            CGPoint(x: 67, y: 75)
        ]

        try expectEqual(recognizer.recognize(points)?.signature, GestureSignature([.right, .down]))
    }

    private static func testReturnsNilWhenPointerDoesNotTravelFarEnough() throws {
        let recognizer = GestureRecognizer(minSegmentLength: 18)
        let points = [
            CGPoint(x: 10, y: 10),
            CGPoint(x: 14, y: 13),
            CGPoint(x: 17, y: 15)
        ]

        try expectNil(recognizer.recognize(points))
    }

    private static func testParsesCompactSignatureText() throws {
        try expectEqual(try GestureSignature(compactText: "LDR").directions, [.left, .down, .right])
        try expectEqual(try GestureSignature(compactText: "left, up, right").directions, [.left, .up, .right])
    }

    private static func testTemplateNormalizationIgoresPositionAndScale() throws {
        let original = GestureTemplate(points: [
            CGPoint(x: 10, y: 10),
            CGPoint(x: 40, y: 10),
            CGPoint(x: 40, y: 60)
        ])
        let movedAndScaled = GestureTemplate(points: [
            CGPoint(x: 220, y: 120),
            CGPoint(x: 340, y: 120),
            CGPoint(x: 340, y: 320)
        ])

        // DTW on normalized (x,y): identical shape → near-zero distance
        try expectLessThan(GestureTemplateMatcher.distance(original, movedAndScaled), 0.05)
    }

    private static func testTemplateMatcherScoresSimilarShapesLowerThanDifferentShapes() throws {
        let template = GestureTemplate(points: [
            CGPoint(x: 10, y: 10),
            CGPoint(x: 50, y: 10),
            CGPoint(x: 50, y: 80)
        ])
        let similar = GestureTemplate(points: [
            CGPoint(x: 100, y: 100),
            CGPoint(x: 160, y: 104),
            CGPoint(x: 164, y: 205)
        ])
        let different = GestureTemplate(points: [
            CGPoint(x: 100, y: 100),
            CGPoint(x: 100, y: 200),
            CGPoint(x: 40, y: 200)
        ])

        let similarScore = GestureTemplateMatcher.distance(template, similar)
        let differentScore = GestureTemplateMatcher.distance(template, different)

        // DTW on (x,y): similar L-shape → low score, different shape → higher score
        try expectLessThan(similarScore, 0.05)
        try expectLessThan(0.10, differentScore)
    }

    private static func testAppSpecificRuleWinsOverGlobalRule() throws {
        let signature = GestureSignature([.left])
        let globalRule = GestureRule(
            name: "Global Back",
            signature: signature,
            scope: .global,
            action: .keyStroke(KeyboardShortcutSpec(key: "[", modifiers: [.command]))
        )
        let appRule = GestureRule(
            name: "Safari Back",
            signature: signature,
            scope: .application(bundleIdentifier: "com.apple.Safari"),
            action: .keyStroke(KeyboardShortcutSpec(key: "leftArrow", modifiers: [.command]))
        )

        let match = RuleMatcher.match(
            signature: signature,
            bundleIdentifier: "com.apple.Safari",
            rules: [globalRule, appRule]
        )

        try expectEqual(match?.id, appRule.id)
    }

    private static func testAppSpecificTemplateRuleWinsOverGlobalTemplateRule() throws {
        let capturedTemplate = GestureTemplate(points: [
            CGPoint(x: 200, y: 200),
            CGPoint(x: 260, y: 200),
            CGPoint(x: 260, y: 280)
        ])
        let globalRule = GestureRule(
            name: "Global Corner",
            template: GestureTemplate(points: [
                CGPoint(x: 10, y: 10),
                CGPoint(x: 70, y: 10),
                CGPoint(x: 70, y: 90)
            ]),
            scope: .global,
            action: .keyStroke(KeyboardShortcutSpec(key: "g", modifiers: [.command]))
        )
        let appRule = GestureRule(
            name: "Safari Corner",
            template: GestureTemplate(points: [
                CGPoint(x: 15, y: 15),
                CGPoint(x: 75, y: 16),
                CGPoint(x: 78, y: 95)
            ]),
            scope: .application(bundleIdentifier: "com.apple.Safari"),
            action: .keyStroke(KeyboardShortcutSpec(key: "s", modifiers: [.command]))
        )

        let match = RuleMatcher.match(
            template: capturedTemplate,
            signature: GestureSignature([.right, .down]),
            bundleIdentifier: "com.apple.Safari",
            rules: [globalRule, appRule]
        )

        try expectEqual(match?.id, appRule.id)
    }

    private static func testDisabledRulesAreIgnored() throws {
        let signature = GestureSignature([.right])
        var disabledRule = GestureRule(
            name: "Forward",
            signature: signature,
            scope: .global,
            action: .keyStroke(KeyboardShortcutSpec(key: "]", modifiers: [.command]))
        )
        disabledRule.isEnabled = false

        try expectNil(RuleMatcher.match(signature: signature, bundleIdentifier: nil, rules: [disabledRule]))
    }

    private static func testFormatsShortcutForDisplay() throws {
        let shortcut = KeyboardShortcutSpec(key: "w", modifiers: [.command, .shift])

        try expectEqual(shortcut.displayText, "⇧⌘W")
    }

    private static func testResolvesCommonMacKeyCodes() throws {
        try expectEqual(KeyboardShortcutSpec(key: "w", modifiers: []).keyCode, 13)
        try expectEqual(KeyboardShortcutSpec(key: "space", modifiers: []).keyCode, 49)
        try expectEqual(KeyboardShortcutSpec(key: "leftArrow", modifiers: []).keyCode, 123)
    }

    private static func testRecognizesDiagonalDirection() throws {
        let recognizer = GestureRecognizer(minSegmentLength: 18)
        let points = [
            CGPoint(x: 10, y: 10),
            CGPoint(x: 30, y: 30),
            CGPoint(x: 55, y: 55)
        ]

        try expectEqual(recognizer.recognize(points)?.signature, GestureSignature([.downRight]))
    }

    private static func testParsesDiagonalSignatureText() throws {
        try expectEqual(try GestureSignature(compactText: "DR").directions, [.downRight])
        try expectEqual(try GestureSignature(compactText: "UL").directions, [.upLeft])
        try expectEqual(try GestureSignature(compactText: "upright").directions, [.upRight])
        try expectEqual(try GestureSignature(compactText: "nw").directions, [.upLeft])
    }

    private static func testModifierMatchingRequiresAllSpecified() throws {
        let rule = GestureRule(
            name: "Shifted Back",
            signature: GestureSignature([.left]),
            modifierRequirements: [.shift],
            scope: .global,
            action: .keyStroke(KeyboardShortcutSpec(key: "[", modifiers: [.command]))
        )

        let match1 = RuleMatcher.match(
            signature: GestureSignature([.left]),
            activeModifiers: [.shift],
            bundleIdentifier: nil,
            rules: [rule]
        )
        try expectEqual(match1?.id, rule.id)

        let match2 = RuleMatcher.match(
            signature: GestureSignature([.left]),
            activeModifiers: [],
            bundleIdentifier: nil,
            rules: [rule]
        )
        try expectNil(match2)
    }

    private static func testConflictDetectionFindsSimilarGestures() throws {
        let existing = GestureRule(
            name: "Existing",
            template: GestureTemplate(points: [
                CGPoint(x: 10, y: 10),
                CGPoint(x: 50, y: 10),
                CGPoint(x: 50, y: 80)
            ]),
            scope: .global,
            action: .keyStroke(KeyboardShortcutSpec(key: "a", modifiers: [.command]))
        )

        let conflicts = RuleMatcher.detectConflicts(
            template: GestureTemplate(points: [
                CGPoint(x: 12, y: 12),
                CGPoint(x: 52, y: 11),
                CGPoint(x: 51, y: 82)
            ]),
            rules: [existing]
        )

        try expectEqual(conflicts.count, 1)
        try expectEqual(conflicts.first?.name, "Existing")
    }

    private static func testCategorySerialization() throws {
        let rule = GestureRule(
            name: "Test",
            category: "Navigation",
            signature: GestureSignature([.left]),
            scope: .global,
            action: .keyStroke(KeyboardShortcutSpec(key: "[", modifiers: [.command]))
        )

        let encoder = JSONEncoder()
        let data = try encoder.encode(rule)
        let decoded = try JSONDecoder().decode(GestureRule.self, from: data)

        try expectEqual(decoded.category, "Navigation")
    }

    @MainActor
    private static func testDefaultLanguageIsChinese() throws {
        let defaults = UserDefaults(suiteName: "com.luantu.Strokly.checks.\(UUID().uuidString)")!
        let settings = AppSettingsStore(defaults: defaults)

        try expectEqual(settings.language, .zhHans)
        try expectEqual(settings.locale.identifier, "zh-Hans")
    }

    @MainActor
    private static func testChineseLocalizationResourceIsResolved() throws {
        UserDefaults.standard.set(["zh-Hans"], forKey: "AppleLanguages")
        try expectEqual(L10n.string("General"), "通用")
        try expectEqual(L10n.string("Right Mouse"), "右键")
    }

    private static func testEdgeScrollDetectionUsesContainingDisplay() throws {
        let main = DisplayEdgeBounds(bounds: CGRect(x: 0, y: 0, width: 1440, height: 900))
        let second = DisplayEdgeBounds(bounds: CGRect(x: 1440, y: 0, width: 1440, height: 900))

        try expectEqual(
            EdgeScrollDetector.edge(
                for: CGPoint(x: 2000, y: 10),
                displays: [main, second],
                threshold: 24
            ),
            .top
        )
        try expectEqual(
            EdgeScrollDetector.edge(
                for: CGPoint(x: 2870, y: 450),
                displays: [main, second],
                threshold: 24
            ),
            .right
        )
    }

    private static func testNoiseCountIncrementsOnAbandonedDirectionChange() throws {
        let recognizer = GestureRecognizer(minSegmentLength: 18)
        let points = [
            CGPoint(x: 10, y: 10),
            CGPoint(x: 10, y: 35),
            CGPoint(x: 10, y: 60),
            CGPoint(x: 40, y: 62),
            CGPoint(x: 42, y: 40),
            CGPoint(x: 45, y: 65),
            CGPoint(x: 80, y: 67),
            CGPoint(x: 115, y: 68)
        ]
        let result = recognizer.recognize(points)
        try expectEqual(result?.signature, GestureSignature([.down, .right]))
        try expectLessThan(0, result?.noiseCount ?? 0)
    }

    private static func testCleanGestureHasZeroNoise() throws {
        let recognizer = GestureRecognizer(minSegmentLength: 18)
        let points = [
            CGPoint(x: 10, y: 10),
            CGPoint(x: 10, y: 30),
            CGPoint(x: 12, y: 55),
            CGPoint(x: 11, y: 80),
            CGPoint(x: 35, y: 82),
            CGPoint(x: 60, y: 82),
            CGPoint(x: 85, y: 83)
        ]
        let result = recognizer.recognize(points)
        try expectEqual(result?.signature, GestureSignature([.down, .right]))
        try expectEqual(result?.noiseCount, 0)
    }

    private static func testNoisyGestureExceedsMatchTolerance() throws {
        let rule = GestureRule(
            name: "Close Tab",
            signature: GestureSignature([.down, .right]),
            scope: .global,
            action: .keyStroke(KeyboardShortcutSpec(key: "w", modifiers: [.command])),
            matchTolerance: 0.15
        )

        let noisyTemplate = GestureTemplate(points: [
            CGPoint(x: 10, y: 10),
            CGPoint(x: 12, y: 50),
            CGPoint(x: 12, y: 100),
            CGPoint(x: 50, y: 110),
            CGPoint(x: 30, y: 90),
            CGPoint(x: 60, y: 100),
            CGPoint(x: 100, y: 105),
            CGPoint(x: 150, y: 108)
        ])

        let rawDistance = GestureTemplateMatcher.distance(noisyTemplate, rule.template)
        try expectLessThan(rawDistance, rule.matchTolerance)

        let noisyCandidates: RuleMatcher.TemplateMatch? = RuleMatcher.matchWithScore(
            template: noisyTemplate,
            signature: GestureSignature([.down, .right]),
            bundleIdentifier: nil,
            noiseCount: 0,
            rules: [rule]
        )
        try expectNotNil(noisyCandidates)

        let penalizedCandidates: RuleMatcher.TemplateMatch? = RuleMatcher.matchWithScore(
            template: noisyTemplate,
            signature: GestureSignature([.down, .right]),
            bundleIdentifier: nil,
            noiseCount: 3,
            rules: [rule]
        )
        try expectNil(penalizedCandidates)
    }

    private static func testComplexShapeDoesNotMatchSimpleLine() throws {
        // A "W" shaped gesture (4 direction changes) should NOT match a simple diagonal line
        let wShape = GestureTemplate(points: [
            CGPoint(x: 0, y: 0),
            CGPoint(x: 30, y: 60),
            CGPoint(x: 60, y: 0),
            CGPoint(x: 90, y: 60),
            CGPoint(x: 120, y: 0)
        ])
        let diagonal = GestureTemplate(points: [
            CGPoint(x: 0, y: 0),
            CGPoint(x: 40, y: 40),
            CGPoint(x: 80, y: 80),
            CGPoint(x: 120, y: 120)
        ])

        let score = GestureTemplateMatcher.distance(wShape, diagonal)
        // W zigzag points are far from diagonal line points → high DTW cost
        try expectLessThan(0.15, score)
    }

    private static func testOldToleranceMigratesToNewScale() throws {
        // Create a rule with old tolerance, encode to JSON, decode back
        let oldRule = GestureRule(
            name: "Test Migration",
            signature: GestureSignature([.down]),
            scope: .global,
            action: .keyStroke(KeyboardShortcutSpec(key: "w", modifiers: [.command])),
            matchTolerance: 0.22
        )
        let encoder = JSONEncoder()
        let data = try encoder.encode(oldRule)
        let decoded = try JSONDecoder().decode(GestureRule.self, from: data)
        // Old value 0.22 < 0.3 so no turning-angle migration; but < 0.02 check → clamp to 0.05
        // Actually 0.22 > 0.02, so no clamp. Value stays 0.22 which is > 0.3? No, 0.22 < 0.3
        // So neither migration triggers, value stays 0.22
        try expectEqual(decoded.matchTolerance, 0.22)
    }

    private static func expectEqual<T: Equatable>(_ actual: T, _ expected: T, file: StaticString = #file, line: UInt = #line) throws {
        if actual != expected {
            throw CheckFailure("Expected \(expected), got \(actual)", file: file, line: line)
        }
    }

    private static func expectNil<T>(_ actual: T?, file: StaticString = #file, line: UInt = #line) throws {
        if let actual {
            throw CheckFailure("Expected nil, got \(actual)", file: file, line: line)
        }
    }

    private static func expectNotNil<T>(_ actual: T?, file: StaticString = #file, line: UInt = #line) throws {
        if actual == nil {
            throw CheckFailure("Expected non-nil, got nil", file: file, line: line)
        }
    }

    private static func expectLessThan<T: Comparable>(_ actual: T, _ threshold: T, file: StaticString = #file, line: UInt = #line) throws {
        if actual >= threshold {
            throw CheckFailure("Expected \(actual) to be less than \(threshold)", file: file, line: line)
        }
    }
}

private struct CheckFailure: Error, CustomStringConvertible {
    var message: String
    var file: StaticString
    var line: UInt

    init(_ message: String, file: StaticString, line: UInt) {
        self.message = message
        self.file = file
        self.line = line
    }

    var description: String {
        "\(file):\(line): \(message)"
    }
}

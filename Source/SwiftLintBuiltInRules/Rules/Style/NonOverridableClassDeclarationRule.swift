import SwiftSyntax

struct NonOverridableClassDeclarationRule: SwiftSyntaxRule, CorrectableRule, ConfigurationProviderRule, OptInRule {
    var configuration = NonOverridableClassDeclarationConfiguration()

    static var description = RuleDescription(
        identifier: "non_overridable_class_declaration",
        name: "Class Declaration in Final Class",
        description: """
            Class methods and properties in final classes should themselves be final, just as if the declarations
            are private. In both cases, they cannot be overriden. Using `final class` or `static` makes this explicit.
        """,
        kind: .style,
        nonTriggeringExamples: [
            Example("""
            final class C {
                final class var b: Bool { true }
                final class func f() {}
            }
            """),
            Example("""
            class C {
                final class var b: Bool { true }
                final class func f() {}
            }
            """),
            Example("""
            class C {
                class var b: Bool { true }
                class func f() {}
            }
            """),
            Example("""
            class C {
                static var b: Bool { true }
                static func f() {}
            }
            """),
            Example("""
            final class C {
                static var b: Bool { true }
                static func f() {}
            }
            """),
            Example("""
            final class C {
                class D {
                    class var b: Bool { true }
                    class func f() {}
                }
            }
            """)
        ],
        triggeringExamples: [
            Example("""
            final class C {
                ↓class var b: Bool { true }
                ↓class func f() {}
            }
            """),
            Example("""
            class C {
                final class D {
                    ↓class var b: Bool { true }
                    ↓class func f() {}
                }
            }
            """),
            Example("""
            class C {
                private ↓class var b: Bool { true }
                private ↓class func f() {}
            }
            """)
        ],
        corrections: [
            Example("""
            final class C {
                class func f() {}
            }
            """): Example("""
                final class C {
                    final class func f() {}
                }
                """),
            Example("""
            final class C {
                class var b: Bool { true }
            }
            """, configuration: ["final_class_modifier": "static"]): Example("""
                final class C {
                    static var b: Bool { true }
                }
                """)
        ]
    )

    func makeVisitor(file: SwiftLintFile) -> ViolationsSyntaxVisitor {
        Visitor(severity: configuration.severity)
    }

    func correct(file: SwiftLintFile) -> [Correction] {
        let ranges = Visitor(severity: configuration.severity)
            .walk(file: file, handler: \.corrections)
            .compactMap { file.stringView.NSRange(start: $0.start, end: $0.end) }
            .filter { file.ruleEnabled(violatingRange: $0, for: self) != nil }
            .reversed()

        var corrections = [Correction]()
        var contents = file.contents
        for range in ranges {
            let contentsNSString = contents.bridge()
            contents = contentsNSString.replacingCharacters(in: range, with: configuration.finalClassModifier.rawValue)
            let location = Location(file: file, characterOffset: range.location)
            corrections.append(Correction(ruleDescription: Self.description, location: location))
        }

        file.write(contents)

        return corrections
    }
}

private class Visitor: ViolationsSyntaxVisitor {
    private let severity: ViolationSeverity

    private var finalClassScope = Stack<Bool>()
    private(set) var corrections = [(start: AbsolutePosition, end: AbsolutePosition)]()

    override var skippableDeclarations: [DeclSyntaxProtocol.Type] { [ProtocolDeclSyntax.self] }

    init(severity: ViolationSeverity) {
        self.severity = severity
        super.init(viewMode: .sourceAccurate)
    }

    override func visit(_ node: ClassDeclSyntax) -> SyntaxVisitorContinueKind {
        finalClassScope.push(node.modifiers.isFinal)
        return .visitChildren
    }

    override func visitPost(_ node: ClassDeclSyntax) {
        _ = finalClassScope.pop()
    }

    override func visitPost(_ node: FunctionDeclSyntax) {
        checkViolations(for: node.modifiers, type: "methods")
    }

    override func visitPost(_ node: VariableDeclSyntax) {
        checkViolations(for: node.modifiers, type: "properties")
    }

    private func checkViolations(for modifiers: ModifierListSyntax?, type: String) {
        guard !modifiers.isFinal, let classKeyword = modifiers?.first(where: { $0.name.text == "class" }),
              case let inFinalClass = finalClassScope.peek() == true, inFinalClass || modifiers.isPrivate else {
            return
        }
        violations.append(ReasonedRuleViolation(
            position: classKeyword.positionAfterSkippingLeadingTrivia,
            reason: inFinalClass
                ? "Class \(type) in final classes should themselves be final"
                : "Private class methods and properties should be declared final",
            severity: severity
        ))
        corrections.append(
            (classKeyword.positionAfterSkippingLeadingTrivia, classKeyword.endPositionBeforeTrailingTrivia)
        )
    }
}

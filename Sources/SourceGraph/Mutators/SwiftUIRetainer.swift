import Configuration
import Foundation
import Shared

final class SwiftUIRetainer: SourceGraphMutator {
    private let graph: SourceGraph
    private let configuration: Configuration
    private static let specialProtocolNames = ["LibraryContentProvider"]
    private static let applicationDelegateAdaptorStructNames = ["UIApplicationDelegateAdaptor", "NSApplicationDelegateAdaptor"]

    required init(graph: SourceGraph, configuration: Configuration, swiftVersion _: SwiftVersion) {
        self.graph = graph
        self.configuration = configuration
    }

    func mutate() {
        retainSpecialProtocolConformances()
        retainApplicationDelegateAdaptors()
        referenceStateMacroProjectedProperties()
        unretainPreviewMacroExpansions()
    }

    // MARK: - Private

    private func retainSpecialProtocolConformances() {
        var names = Self.specialProtocolNames

        if configuration.retainSwiftUIPreviews {
            names.append("PreviewProvider")
        }

        graph
            .declarations(ofKinds: [.class, .struct, .enum])
            .lazy
            .filter {
                $0.related.contains {
                    self.graph.isExternal($0) && $0.declarationKind == .protocol && names.contains($0.name)
                }
            }
            .forEach { graph.markRetained($0) }
    }

    private func retainApplicationDelegateAdaptors() {
        graph
            .mainAttributedDeclarations
            .lazy
            .flatMap(\.declarations)
            .filter { $0.kind == .varInstance }
            .filter {
                $0.references.contains {
                    ($0.declarationKind == .struct || $0.declarationKind == .enum) && Self.applicationDelegateAdaptorStructNames.contains($0.name)
                }
            }
            .forEach { graph.markRetained($0) }
    }

    private func referenceStateMacroProjectedProperties() {
        for property in graph.declarations(ofKind: .varInstance) where property.attributes.contains(where: { $0.name == "State" }) {
            guard let propertyUsr = property.usrs.first,
                  let projected = property.parent?.declarations.first(where: {
                      $0.isImplicit && $0.name == "$\(property.name)" && $0.location.file == property.location.file
                  })
            else { continue }

            // The projected binding is a macro-generated peer, not a child of the declared property.
            for use in graph.references(to: projected) where use.kind == .normal {
                guard let parent = use.parent, !parent.isImplicit else { continue }

                let reference = Reference(
                    name: property.name,
                    kind: .normal,
                    declarationKind: property.kind,
                    usr: propertyUsr,
                    location: use.location
                )
                reference.parent = parent
                graph.add(reference, from: parent)
            }
        }
    }

    private func unretainPreviewMacroExpansions() {
        guard !configuration.retainSwiftUIPreviews else { return }

        let previewRegistryUsr = "s:21DeveloperToolsSupport15PreviewRegistryP"
        let macroReferences = graph.references(to: previewRegistryUsr)
        guard !macroReferences.isEmpty else { return }

        for reference in macroReferences {
            if let parent = reference.parent, parent.isImplicit {
                graph.unmarkRetained(parent)

                for decl in parent.declarations {
                    graph.unmarkRetained(decl)
                }
            }
        }
    }
}

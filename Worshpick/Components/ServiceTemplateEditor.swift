import SwiftUI
import WorshpickCore

struct ServiceTemplateEditor: View {
    let templates: [ServiceTemplate]
    let momentOptions: [String]
    let invitationOptions: [String]
    let onChange: ([ServiceTemplate]) -> Void

    var body: some View {
        ForEach(templates) { template in
            DisclosureGroup {
                ForEach(template.slots) { slot in
                    slotEditor(slot, in: template)
                }
                HStack {
                    Button("Añadir hueco") {
                        update(template) { $0.slots.append(ServiceSlot(label: "Canción \($0.slots.count + 1)")) }
                    }
                    Spacer()
                    Button("Eliminar plantilla", role: .destructive) { onChange(templates.filter { $0.id != template.id }) }
                }
                .controlSize(.small)
            } label: {
                TextField("Nombre", text: Binding(get: { template.name }, set: { newName in update(template) { $0.name = newName } }))
                    .textFieldStyle(.plain)
                    .font(.headline)
            }
        }
        Button("Nueva plantilla") {
            onChange(templates + [ServiceTemplate(name: "Nueva plantilla", slots: [ServiceSlot(label: "Apertura", moment: "Apertura")])])
        }
    }

    private func slotEditor(_ slot: ServiceSlot, in template: ServiceTemplate) -> some View {
        HStack {
            TextField("Etiqueta", text: Binding(get: { slot.label }, set: { newLabel in updateSlot(slot, in: template) { $0.label = newLabel } }))
                .frame(width: 110)
            optionalPicker("Momento", selection: slot.moment, options: momentOptions) { newMoment in updateSlot(slot, in: template) { $0.moment = newMoment } }
            optionalPicker("Invitación", selection: slot.invitation, options: invitationOptions) { newInvitation in updateSlot(slot, in: template) { $0.invitation = newInvitation } }
            Picker("Energía", selection: Binding(get: { slot.energy }, set: { newEnergy in updateSlot(slot, in: template) { $0.energy = newEnergy } })) {
                Text("Cualquiera").tag(Energy?.none)
                ForEach(Energy.allCases, id: \.self) { Text(DisplayFormatting.energy($0)).tag(Optional($0)) }
            }
            .labelsHidden()
            .fixedSize()
            Button { update(template) { $0.slots.removeAll { $0.id == slot.id } } } label: { Image(systemName: "minus.circle") }
                .buttonStyle(.borderless)
        }
        .controlSize(.small)
    }

    private func optionalPicker(_ title: String, selection: String?, options: [String], onChange: @escaping (String?) -> Void) -> some View {
        Picker(title, selection: Binding(get: { selection }, set: onChange)) {
            Text("\(title): cualquiera").tag(String?.none)
            ForEach(options, id: \.self) { Text($0).tag(Optional($0)) }
        }
        .labelsHidden()
        .fixedSize()
    }

    private func update(_ template: ServiceTemplate, change: (inout ServiceTemplate) -> Void) {
        var updatedTemplates = templates
        guard let templateIndex = updatedTemplates.firstIndex(where: { $0.id == template.id }) else { return }
        change(&updatedTemplates[templateIndex])
        onChange(updatedTemplates)
    }

    private func updateSlot(_ slot: ServiceSlot, in template: ServiceTemplate, change: @escaping (inout ServiceSlot) -> Void) {
        update(template) { editedTemplate in
            guard let slotIndex = editedTemplate.slots.firstIndex(where: { $0.id == slot.id }) else { return }
            change(&editedTemplate.slots[slotIndex])
        }
    }
}

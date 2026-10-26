// RememberListView.swift
// Local editable "Recordá esto" list of facts

import SwiftUI
import SwiftData

struct RememberListView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    
    @StateObject private var rememberService = RememberListService()
    
    @State private var showAddSheet = false
    @State private var editingFact: RememberListItem?
    @State private var newFactText = ""
    @State private var selectedCategory = "general"
    
    let categories = [
        ("general", "General"),
        ("birthday", "Cumpleaños"),
        ("relationship", "Relaciones"),
        ("place", "Lugares")
    ]
    
    var body: some View {
        NavigationStack {
            ZStack {
                MomentsColors.bgPrimary.ignoresSafeArea()
                
                if rememberService.facts.isEmpty {
                    emptyState
                } else {
                    factsList
                }
            }
            .navigationTitle(Text("remember_list_title"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        showAddSheet = true
                    } label: {
                        Image(systemName: "plus")
                    }
                }
            }
            .onAppear {
                rememberService.initialize(modelContext: modelContext)
            }
            .sheet(isPresented: $showAddSheet) {
                addFactSheet
            }
            .sheet(item: $editingFact) { fact in
                editFactSheet(fact: fact)
            }
        }
    }
    
    // MARK: - Empty State
    
    private var emptyState: some View {
        VStack(spacing: MomentsSpacing.lg) {
            Image(systemName: "brain.head.profile")
                .font(.system(size: 64))
                .foregroundStyle(MomentsColors.textTertiary)
            
            Text("remember_list_empty")
                .font(MomentsTypography.headlineMedium)
                .foregroundStyle(MomentsColors.textPrimary)
            
            Text("remember_list_empty_description")
                .font(MomentsTypography.bodyMedium)
                .foregroundStyle(MomentsColors.textSecondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, MomentsSpacing.xl)
            
            Button {
                showAddSheet = true
            } label: {
                HStack {
                    Image(systemName: "plus.circle.fill")
                    Text("remember_list_add")
                }
            }
            .momentsAccentButton()
            .padding(.horizontal, MomentsSpacing.screenHorizontal)
        }
    }
    
    // MARK: - Facts List
    
    private var factsList: some View {
        List {
            // Group by category
            ForEach(categories, id: \.0) { categoryKey, categoryName in
                let categoryFacts = rememberService.getFacts(category: categoryKey)
                
                if !categoryFacts.isEmpty {
                    Section {
                        ForEach(categoryFacts, id: \.id) { fact in
                            FactRow(fact: fact) {
                                editingFact = fact
                            }
                            .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                                Button(role: .destructive) {
                                    Task {
                                        await rememberService.deleteFact(id: fact.id)
                                    }
                                } label: {
                                    Label("Eliminar", systemImage: "trash")
                                }
                            }
                        }
                    } header: {
                        Text(categoryName)
                    }
                }
            }
        }
        .listStyle(.insetGrouped)
        .scrollContentBackground(.hidden)
    }
    
    // MARK: - Add Fact Sheet
    
    private var addFactSheet: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("Escribí un dato...", text: $newFactText, axis: .vertical)
                        .lineLimit(3...6)
                } header: {
                    Text("Dato")
                } footer: {
                    Text("Ej: \"El cumpleaños de María es el 15 de marzo\" o \"Sofía es la hija de Juan\"")
                }
                
                Section {
                    Picker("Categoría", selection: $selectedCategory) {
                        ForEach(categories, id: \.0) { key, name in
                            Text(name).tag(key)
                        }
                    }
                } header: {
                    Text("Categoría")
                }
            }
            .navigationTitle("Agregar dato")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Cancelar") {
                        newFactText = ""
                        showAddSheet = false
                    }
                }
                
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Guardar") {
                        Task {
                            await rememberService.addFact(
                                newFactText.trimmingCharacters(in: .whitespacesAndNewlines),
                                category: selectedCategory,
                                source: "user"
                            )
                            newFactText = ""
                            showAddSheet = false
                        }
                    }
                    .disabled(newFactText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
        }
        .presentationDetents([.medium])
    }
    
    // MARK: - Edit Fact Sheet
    
    private func editFactSheet(fact: RememberListItem) -> some View {
        NavigationStack {
            Form {
                Section {
                    TextField("Dato", text: Binding(
                        get: { fact.fact },
                        set: { fact.fact = $0 }
                    ), axis: .vertical)
                    .lineLimit(3...6)
                } header: {
                    Text("Dato")
                }
                
                Section {
                    if fact.source == "cataloging" {
                        Label("Aprendido de catalogación", systemImage: "sparkles")
                            .foregroundStyle(MomentsColors.textSecondary)
                    } else if fact.source == "user" {
                        Label("Agregado por vos", systemImage: "person.fill")
                            .foregroundStyle(MomentsColors.textSecondary)
                    }
                    
                    if fact.isUserEdited {
                        Label("Editado", systemImage: "pencil")
                            .foregroundStyle(MomentsColors.textSecondary)
                    }
                } header: {
                    Text("Origen")
                }
            }
            .navigationTitle("Editar dato")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Cancelar") {
                        editingFact = nil
                    }
                }
                
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Guardar") {
                        Task {
                            await rememberService.updateFact(id: fact.id, newFact: fact.fact)
                            editingFact = nil
                        }
                    }
                }
            }
        }
        .presentationDetents([.medium])
    }
}

// MARK: - Fact Row

struct FactRow: View {
    let fact: RememberListItem
    let onEdit: () -> Void
    
    var body: some View {
        Button {
            onEdit()
        } label: {
            VStack(alignment: .leading, spacing: 4) {
                Text(fact.fact)
                    .font(MomentsTypography.bodyMedium)
                    .foregroundStyle(MomentsColors.textPrimary)
                
                HStack(spacing: MomentsSpacing.xs) {
                    if let personName = fact.personName {
                        Label(personName, systemImage: "person.fill")
                            .font(MomentsTypography.caption)
                            .foregroundStyle(MomentsColors.textTertiary)
                    }
                    
                    if fact.isUserEdited {
                        Label("Editado", systemImage: "pencil")
                            .font(MomentsTypography.caption)
                            .foregroundStyle(MomentsColors.textTertiary)
                    }
                }
            }
        }
    }
}

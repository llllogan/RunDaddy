//
//  Dashboard.swift
//  PickAgent
//
//  Created by Logan Janssen on 4/11/2025.
//

import SwiftUI

struct DashboardView: View {
    let session: AuthSession
    let logoutAction: () -> Void

    @StateObject private var viewModel: DashboardViewModel
    @State private var isShowingProfile = false
    @Namespace private var profileNamespace
    
    private var hasCompany: Bool {
        // User has company if they have company memberships
        viewModel.currentUserProfile?.hasCompany ?? false
    }

    init(session: AuthSession, logoutAction: @escaping () -> Void) {
        self.session = session
        self.logoutAction = logoutAction
        _viewModel = StateObject(wrappedValue: DashboardViewModel(session: session))
    }

    var body: some View {
        NavigationStack {
            List {
                if let message = viewModel.errorMessage {
                    Section {
                        ErrorStateRow(message: message)
                    }
                }

                // Only show "Runs for Today" section if there are runs or currently loading
                if !viewModel.todayRuns.isEmpty || (viewModel.isLoading && viewModel.todayRuns.isEmpty) {
                    Section("Runs for Today") {
                        if viewModel.isLoading && viewModel.todayRuns.isEmpty {
                            LoadingStateRow()
                        } else {
                            ForEach(viewModel.todayRuns) { run in
                                NavigationLink {
                                    RunDetailView(runId: run.id, session: session)
                                } label: {
                                    RunRow(run: run)
                                }
                            }
                            Text("View 2 more")
                        }
                    }
                }

                // Only show "Runs to be Packed" section if there are runs or currently loading
                if !viewModel.runsToPack.isEmpty || (viewModel.isLoading && viewModel.runsToPack.isEmpty) {
                    Section("Runs to be Packed") {
                        if viewModel.isLoading && viewModel.runsToPack.isEmpty {
                            LoadingStateRow()
                        } else {
                            ForEach(viewModel.runsToPack) { run in
                                NavigationLink {
                                    RunDetailView(runId: run.id, session: session)
                                } label: {
                                    RunRow(run: run)
                                }
                            }
                            Text("View 5 more")
                        }
                    }
                }

                Section("All Runs") {
                    NavigationLink {
                        AllRunsView(session: session)
                    } label: {
                        HStack {
                            Text("View All Runs")
                                .foregroundStyle(.primary)
                        }
                    }
                    .buttonStyle(.plain)
                }

                Section("Insights") {
                    EmptyStateRow(message: "Insights will show up once you start running orders.")
                }
            }
            .listStyle(.insetGrouped)
            .navigationTitle("Hello \(session.profile.displayName)")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        withAnimation(.spring(response: 0.45, dampingFraction: 0.82)) {
                            isShowingProfile = true
                        }
                    } label: {
                        Label("Profile", systemImage: "person.fill")
                    }
                }
                .matchedTransitionSource(id: "profile", in: profileNamespace)
            }
        }
        .task {
            await viewModel.loadRuns()
        }
        .refreshable {
            await viewModel.loadRuns(force: true)
        }
        .sheet(isPresented: $isShowingProfile) {
            ProfileSheetView(
                profileNamespace: profileNamespace,
                session: session,
                logoutAction: logoutAction,
                namespace: profileNamespace,
                isPresented: $isShowingProfile,
                hasCompany: hasCompany,
                viewModel: viewModel
            )
            .presentationDetents([.large])
            .presentationCornerRadius(28)
            .presentationDragIndicator(.visible)
            .presentationCompactAdaptation(.fullScreenCover)
        }

    }
}




private enum ProfilePresentation {
    static let matchID = "profile-badge"
}

private struct ProfileSheetView: View {
    
    var profileNamespace: Namespace.ID
    
    let session: AuthSession
    let logoutAction: () -> Void
    let namespace: Namespace.ID
    @Binding var isPresented: Bool
    let hasCompany: Bool
    @ObservedObject var viewModel: DashboardViewModel

    @Environment(\.dismiss) private var dismiss

    private var profile: UserProfile { session.profile }
    private var credentials: AuthCredentials { session.credentials }

    private var tokenExpirationText: String {
        credentials.expiresAt.formatted(.dateTime.month().day().year().hour().minute())
    }
    
    private var initials: String {
        let components = session.profile.displayName.split(separator: " ")
        let firstInitial = components.first?.first
        let secondInitial = components.dropFirst().first?.first
        if let first = firstInitial, let second = secondInitial {
            return String([first, second]).uppercased()
        } else if let first = firstInitial {
            return String(first).uppercased()
        }
        return String(session.profile.email.prefix(1)).uppercased()
    }

    var body: some View {
        NavigationStack {
            List {
                Section {
                    HStack {
                        ZStack {
                            Circle()
                                .fill(Theme.packageBrown.opacity(0.15))
                                .frame(maxWidth: 60)

                            Text(initials)
                                .foregroundStyle(Theme.packageBrown)
                        }

                        VStack(alignment: .leading) {
                            Text(session.profile.displayName)
                                .fontWeight(.semibold)

                            Text(session.profile.email)
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                        }
                    }
                    .matchedGeometryEffect(id: ProfilePresentation.matchID, in: namespace, isSource: false)
                    
                    HStack {
                        Text(hasCompany ? "Company" : "No Company")
                        
                        Spacer()
                        
                        if hasCompany, let companies = viewModel.currentUserProfile?.companies, !companies.isEmpty {
                            Menu {
                                ForEach(companies, id: \.id) { company in
                                    Button(company.name) {
                                        // TODO: Implement company switching
                                    }
                                }
                            } label: {
                                Label("Switch", systemImage: "arrow.up.arrow.down.circle")
                                    .labelStyle(.titleOnly)
                            }
                        }
                    }
                }
                
                if !hasCompany {
                    Section {
                        VStack(alignment: .leading, spacing: 12) {
                            HStack {
                                Image(systemName: "info.circle.fill")
                                    .foregroundStyle(.blue)
                                Text("No Company Membership")
                                    .font(.headline.weight(.semibold))
                                    .foregroundStyle(.primary)
                            }
                            
                            Text("You're currently logged in without a company. To access runs and other features, you'll need to join or create a company.")
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                        .padding(.vertical, 4)
                    }
                }
                
                Section {
                    ProfileInfoSection(title: "User Information") {
                        ProfileInfoRow(label: "Name", value: profile.displayName)
                        ProfileInfoRow(label: "Email", value: profile.email)
                        if let phone = profile.phone, !phone.isEmpty {
                            ProfileInfoRow(label: "Phone", value: phone)
                        }
                        if let role = profile.role, !role.isEmpty {
                            ProfileInfoRow(label: "Role", value: role)
                        }
                    }
                }
                
                Section {
                    ProfileInfoSection(title: "Authentication") {
                        ProfileInfoRow(label: "User ID", value: credentials.userID)
                        ProfileInfoRow(label: "Access Token", value: credentials.accessToken, monospaced: true)
                        ProfileInfoRow(label: "Expires", value: tokenExpirationText)
                    }
                }
                
                Section {
                    Button(role: .destructive) {
                        dismissSheet(afterDismiss: logoutAction)
                    } label: {
                        Label("Log Out", systemImage: "rectangle.portrait.and.arrow.right")
                            .frame(maxWidth: .infinity)
                            .labelStyle(.titleOnly)
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(.red)
                    .listRowInsets(.init(top: 8, leading: 0, bottom: 8, trailing: 0))
                    .listRowBackground(Color.clear)
                    .listRowSeparator(.hidden)
                }
            }
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        dismissSheet()
                    } label: {
                        Label("Done", systemImage: "xmark")
                    }
                }
            }
            .onDisappear {
                if isPresented {
                    isPresented = false
                }
            }
            .navigationTransition(.zoom(sourceID: "profile", in: profileNamespace))
        }
    }

    private func dismissSheet(afterDismiss: (() -> Void)? = nil) {
        withAnimation(.spring(response: 0.45, dampingFraction: 0.82)) {
            isPresented = false
        }
        dismiss()
        if let afterDismiss {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                afterDismiss()
            }
        }
    }
}

private struct ProfileInfoSection<Content: View>: View {
    let title: String
    @ViewBuilder var content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(title)
                .font(.title3.weight(.semibold))
                .foregroundStyle(.primary)

            VStack(spacing: 10) {
                content
            }
        }
    }
}

private struct ProfileInfoRow: View {
    let label: String
    let value: String
    var monospaced = false

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(label.uppercased())
                .font(.caption)
                .foregroundStyle(.secondary)
            Text(value)
                .font(monospaced ? .system(.subheadline, design: .monospaced) : .subheadline)
                .foregroundStyle(.primary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

private struct ProfileBadgeView: View {
    enum Style {
        case compact
        case expanded
    }

    let user: UserProfile
    let style: Style

    private var initials: String {
        let components = user.displayName.split(separator: " ")
        let firstInitial = components.first?.first
        let secondInitial = components.dropFirst().first?.first
        switch style {
        case .compact:
            if let first = firstInitial {
                return String(first).uppercased()
            }
        case .expanded:
            if let first = firstInitial, let second = secondInitial {
                return String([first, second]).uppercased()
            } else if let first = firstInitial {
                return String(first).uppercased()
            }
        }
        return String(user.email.prefix(1)).uppercased()
    }

    private var titleFont: Font {
        switch style {
        case .compact:
            return .callout.weight(.semibold)
        case .expanded:
            return .title2.weight(.semibold)
        }
    }

    var body: some View {
        HStack(spacing: style == .compact ? 8 : 16) {
            ZStack {
                Circle()
                    .fill(Theme.packageBrown.opacity(0.15))
                    .frame(width: style == .compact ? 32 : 64, height: style == .compact ? 32 : 64)

                Text(initials)
                    .font(style == .compact ? .footnote.weight(.bold) : .title3.weight(.bold))
                    .foregroundStyle(Theme.packageBrown)
            }

            VStack(alignment: .leading, spacing: style == .compact ? 0 : 4) {
                Text(user.displayName)
                    .font(titleFont)

                switch style {
                case .compact:
                    Text("Profile")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                case .expanded:
                    Text(user.email)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
            }

            if style == .compact {
                Image(systemName: "chevron.up")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                    .padding(.leading, 4)
            }
        }
        .padding(style == .compact ? EdgeInsets(top: 6, leading: 8, bottom: 6, trailing: 10) : EdgeInsets(top: 12, leading: 12, bottom: 12, trailing: 12))
        .background(compactBackground)
        .clipShape(Capsule())
    }

    @ViewBuilder
    private var compactBackground: some View {
        switch style {
        case .compact:
            Capsule()
                .fill(Theme.packageBrown.opacity(0.12))
        case .expanded:
            Capsule()
                .fill(.clear)
        }
    }
}


#Preview("Profile Sheet") {
    ProfileSheetPreviewContainer()
}

#Preview {
    RootView()
        .environmentObject(AuthViewModel(service: PreviewAuthService()))
}

private struct ProfileSheetPreviewContainer: View {
    @Namespace private var namespace
    @State private var isPresented = true

    var body: some View {
        ProfileSheetView(
            profileNamespace: namespace,
            session: .preview,
            logoutAction: {},
            namespace: namespace,
            isPresented: $isPresented,
            hasCompany: true,
            viewModel: DashboardViewModel(session: .preview)
        )
    }
}

private extension AuthSession {
    static var preview: AuthSession {
        let credentials = AuthCredentials(
            accessToken: "preview.access.token",
            refreshToken: "preview.refresh.token",
            userID: "preview-user-id",
            expiresAt: Date().addingTimeInterval(3600)
        )

        let profile = UserProfile(
            id: credentials.userID,
            email: "preview@example.com",
            firstName: "Preview",
            lastName: "User",
            phone: "555-867-5309",
            role: "OWNER"
        )

        return AuthSession(credentials: credentials, profile: profile)
    }
}

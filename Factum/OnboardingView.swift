//
//  OnboardingView.swift
//  Pigeon
//
//  First-launch onboarding flow
//

import SwiftUI
import SwiftData
import Auth
import GoogleSignIn

struct OnboardingView: View {
    @Environment(\.modelContext) private var modelContext
    @State private var currentPage = 0
    @State private var isAnimating = false
    @State private var isSigningIn = false
    @State private var signInError: String?
    @State private var isSignUpMode = false
    @State private var email = ""
    @State private var password = ""
    @State private var displayName = ""
    @State private var username = ""
    @State private var usernameAvailable: Bool? = nil
    @State private var isCheckingUsername = false
    @State private var usernameCheckTask: Task<Void, Never>?
    @State private var confirmPassword = ""
    @State private var signUpSuccess = false
    @State private var showGoogleProfileSetup = false
    @State private var isPrivateAccount = true
    @FocusState private var focusedField: AuthField?
    let onComplete: () -> Void
    
    private enum AuthField {
        case name, email, password, confirm
    }
    
    var body: some View {
        ZStack {
            PigeonTheme.background.ignoresSafeArea()
            
            VStack(spacing: 0) {
                // Pages
                TabView(selection: $currentPage) {
                    welcomePage.tag(0)
                    timelapsePage.tag(1)
                    socialPage.tag(2)
                    getStartedPage.tag(3)
                }
                .tabViewStyle(.page(indexDisplayMode: .never))
                .animation(.easeInOut(duration: 0.35), value: currentPage)
                
                // Page indicator + bottom button — always present for stable layout, fades on page 3
                VStack(spacing: 0) {
                    HStack(spacing: 8) {
                        ForEach(0..<4, id: \.self) { index in
                            RoundedRectangle(cornerRadius: 3)
                                .fill(index == currentPage ? PigeonTheme.accent : PigeonTheme.elevated)
                                .frame(width: index == currentPage ? 24 : 8, height: 8)
                                .animation(.easeInOut(duration: 0.25), value: currentPage)
                        }
                    }
                    .padding(.bottom, 32)
                    
                    Button {
                        withAnimation(.easeInOut(duration: 0.35)) {
                            currentPage += 1
                        }
                    } label: {
                        Text("Next")
                            .font(PigeonTheme.subheadlineFont)
                            .foregroundStyle(PigeonTheme.accentText)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 16)
                            .background(PigeonTheme.accent)
                            .clipShape(RoundedRectangle(cornerRadius: 14))
                    }
                    .buttonStyle(.plain)
                    .padding(.horizontal, 24)
                    .padding(.bottom, 40)
                }
                .opacity(currentPage < 3 ? 1 : 0)
                .animation(.easeInOut(duration: 0.3), value: currentPage)
                .allowsHitTesting(currentPage < 3)
            }
        }
        .ignoresSafeArea(.keyboard)
        .onTapGesture {
            focusedField = nil
        }
        .onOpenURL { url in
            GIDSignIn.sharedInstance.handle(url)
        }

    }
    
    // MARK: - Page 1: Welcome
    
    private var welcomePage: some View {
        VStack(spacing: 24) {
            Spacer()
            
            PigeonIcon(size: 180, color: PigeonTheme.primaryText)
                .scaleEffect(isAnimating ? 1.0 : 0.8)
                .opacity(isAnimating ? 1.0 : 0)
                .animation(.spring(response: 0.8, dampingFraction: 0.6), value: isAnimating)
            
            Text("pigeon.")
                .font(.gloucester(size: 48))
                .foregroundStyle(PigeonTheme.primaryText)
                .tracking(6)
            
            Text("a quiet place to study")
                .font(.gloucester(size: 19))
                .foregroundStyle(PigeonTheme.secondaryText)
            
            Spacer()
        }
        .onAppear { isAnimating = true }
    }
    
    // MARK: - Page 2: Timelapse
    
    private var timelapsePage: some View {
        VStack(spacing: 24) {
            Spacer()
            
            ZStack {
                RoundedRectangle(cornerRadius: 20)
                    .fill(PigeonTheme.cardBackground)
                    .frame(width: 200, height: 160)
                
                VStack(spacing: 12) {
                    Image(systemName: "timelapse")
                        .font(.system(size: 48))
                        .foregroundStyle(PigeonTheme.accent)
                    
                    Text("2h 15m")
                        .font(PigeonTheme.font(20, weight: .bold))
                        .foregroundStyle(PigeonTheme.primaryText)
                }
            }
            
            Text("record the work")
                .font(PigeonTheme.titleFont)
                .foregroundStyle(PigeonTheme.primaryText)
            
            Text("your study sessions become\nshort timelapses — proof\nthat the hours happened")
                .font(PigeonTheme.bodyFont)
                .foregroundStyle(PigeonTheme.secondaryText)
                .multilineTextAlignment(.center)
                .lineSpacing(5)
            
            Spacer()
        }
        .padding(.horizontal, 32)
    }
    
    // MARK: - Page 3: Social
    
    private var socialPage: some View {
        VStack(spacing: 24) {
            Spacer()
            
            ZStack {
                // Stacked avatar bubbles with earthy gradients
                let avatarData: [(String, Color, Color)] = [
                    ("S", Color(red: 0.72, green: 0.55, blue: 0.42), Color(red: 0.58, green: 0.42, blue: 0.32)),
                    ("J", Color(red: 0.55, green: 0.62, blue: 0.50), Color(red: 0.42, green: 0.50, blue: 0.38)),
                    ("P", Color(red: 0.68, green: 0.58, blue: 0.50), Color(red: 0.55, green: 0.45, blue: 0.38)),
                    ("A", Color(red: 0.60, green: 0.52, blue: 0.48), Color(red: 0.48, green: 0.40, blue: 0.36)),
                ]
                HStack(spacing: -12) {
                    ForEach(avatarData, id: \.0) { initial, color1, color2 in
                        Circle()
                            .fill(LinearGradient(colors: [color1, color2], startPoint: .topLeading, endPoint: .bottomTrailing))
                            .frame(width: 52, height: 52)
                            .overlay(
                                Text(initial)
                                    .font(PigeonTheme.font(20, weight: .semibold))
                                    .foregroundStyle(.white)
                            )
                            .overlay(
                                Circle().strokeBorder(PigeonTheme.background, lineWidth: 3)
                            )
                    }
                }
            }
            
            Text("study together")
                .font(PigeonTheme.titleFont)
                .foregroundStyle(PigeonTheme.primaryText)
            
            Text("see what your friends are\nworking on — it's easier to\nshow up when others do too")
                .font(PigeonTheme.bodyFont)
                .foregroundStyle(PigeonTheme.secondaryText)
                .multilineTextAlignment(.center)
                .lineSpacing(5)
            
            Spacer()
        }
        .padding(.horizontal, 32)
    }
    
    // MARK: - Page 4: Get Started
    
    private var passwordsMatch: Bool {
        !password.isEmpty && password == confirmPassword
    }
    
    private var canSignUp: Bool {
        !displayName.isEmpty && !email.isEmpty && password.count >= 6 && passwordsMatch && !isSigningIn
        && username.count >= 3 && usernameAvailable == true
    }
    
    private var getStartedPage: some View {
        ScrollView {
            VStack(spacing: 20) {
                PigeonIcon(size: 80, color: PigeonTheme.primaryText)
                    .padding(.top, 24)
                
                Text(isSignUpMode ? "create an account" : "ready when you are")
                    .font(PigeonTheme.titleFont)
                    .foregroundStyle(PigeonTheme.primaryText)
                
                Text(isSignUpMode ? "so your study sessions follow you" : "sign in to keep your work safe")
                    .font(PigeonTheme.bodyFont)
                    .foregroundStyle(PigeonTheme.secondaryText)
                
                // Sign In / Sign Up toggle
                HStack(spacing: 0) {
                    Button {
                        Haptics.selection()
                        withAnimation(.easeInOut(duration: 0.25)) {
                            isSignUpMode = false
                            signInError = nil
                        }
                    } label: {
                        Text("Sign In")
                            .font(PigeonTheme.subheadlineFont)
                            .foregroundStyle(isSignUpMode ? PigeonTheme.secondaryText : PigeonTheme.primaryText)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 10)
                            .background(isSignUpMode ? Color.clear : PigeonTheme.accent)
                            .clipShape(RoundedRectangle(cornerRadius: 10))
                    }
                    
                    Button {
                        Haptics.selection()
                        withAnimation(.easeInOut(duration: 0.25)) {
                            isSignUpMode = true
                            signInError = nil
                        }
                    } label: {
                        Text("Sign Up")
                            .font(PigeonTheme.subheadlineFont)
                            .foregroundStyle(isSignUpMode ? PigeonTheme.primaryText : PigeonTheme.secondaryText)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 10)
                            .background(isSignUpMode ? PigeonTheme.accent : Color.clear)
                            .clipShape(RoundedRectangle(cornerRadius: 10))
                    }
                }
                .padding(4)
                .background(PigeonTheme.cardBackground)
                .clipShape(RoundedRectangle(cornerRadius: 12))
                .padding(.horizontal, 24)
                
                // Form fields
                VStack(spacing: 12) {
                    if isSignUpMode {
                        TextField("Display Name", text: $displayName)
                            .font(PigeonTheme.bodyFont)
                            .foregroundStyle(PigeonTheme.primaryText)
                            .textContentType(.name)
                            .autocorrectionDisabled()
                            .focused($focusedField, equals: .name)
                            .padding(14)
                            .background(PigeonTheme.cardBackground)
                            .clipShape(RoundedRectangle(cornerRadius: 12))
                            .transition(.opacity.combined(with: .move(edge: .top)))
                        
                        // Username field
                        HStack(spacing: 4) {
                            Text("@")
                                .font(PigeonTheme.bodyFont)
                                .foregroundStyle(PigeonTheme.tertiaryText)
                            TextField("username", text: $username)
                                .font(PigeonTheme.bodyFont)
                                .foregroundStyle(PigeonTheme.primaryText)
                                .textInputAutocapitalization(.never)
                                .autocorrectionDisabled()
                                .onChange(of: username) { _, newValue in
                                    let sanitized = newValue.lowercased().filter { $0.isLetter || $0.isNumber || $0 == "_" }
                                    if sanitized != newValue { username = sanitized }
                                    usernameAvailable = nil
                                    usernameCheckTask?.cancel()
                                    guard sanitized.count >= 3 else { return }
                                    usernameCheckTask = Task {
                                        isCheckingUsername = true
                                        try? await Task.sleep(for: .milliseconds(400))
                                        guard !Task.isCancelled else { return }
                                        usernameAvailable = try? await SupabaseService.shared.isUsernameAvailable(sanitized)
                                        isCheckingUsername = false
                                    }
                                }
                        }
                        .padding(14)
                        .background(PigeonTheme.cardBackground)
                        .clipShape(RoundedRectangle(cornerRadius: 12))
                        .overlay(
                            RoundedRectangle(cornerRadius: 12)
                                .strokeBorder(
                                    usernameAvailable == true ? Color.green.opacity(0.5) :
                                    usernameAvailable == false ? PigeonTheme.destructive.opacity(0.5) :
                                    Color.clear,
                                    lineWidth: 1.5
                                )
                        )
                        .transition(.opacity.combined(with: .move(edge: .top)))
                        
                        if isCheckingUsername {
                            HStack(spacing: 6) {
                                ProgressView().scaleEffect(0.7)
                                Text("Checking...")
                                    .font(PigeonTheme.captionFont)
                                    .foregroundStyle(PigeonTheme.tertiaryText)
                            }
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .transition(.opacity)
                        } else if let available = usernameAvailable {
                            Text(available ? "Username available" : "Username taken")
                                .font(PigeonTheme.captionFont)
                                .foregroundStyle(available ? .green : PigeonTheme.destructive)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .transition(.opacity)
                        }
                    }
                    
                    TextField("Email", text: $email)
                        .font(PigeonTheme.bodyFont)
                        .foregroundStyle(PigeonTheme.primaryText)
                        .keyboardType(.emailAddress)
                        .textContentType(.emailAddress)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .focused($focusedField, equals: .email)
                        .padding(14)
                        .background(PigeonTheme.cardBackground)
                        .clipShape(RoundedRectangle(cornerRadius: 12))
                    
                    SecureField(isSignUpMode ? "Password (min 6 characters)" : "Password", text: $password)
                        .font(PigeonTheme.bodyFont)
                        .foregroundStyle(PigeonTheme.primaryText)
                        .textContentType(isSignUpMode ? .newPassword : .password)
                        .autocorrectionDisabled()
                        .focused($focusedField, equals: .password)
                        .padding(14)
                        .background(PigeonTheme.cardBackground)
                        .clipShape(RoundedRectangle(cornerRadius: 12))
                    
                    if isSignUpMode {
                        SecureField("Confirm Password", text: $confirmPassword)
                            .font(PigeonTheme.bodyFont)
                            .foregroundStyle(PigeonTheme.primaryText)
                            .textContentType(.newPassword)
                            .autocorrectionDisabled()
                            .focused($focusedField, equals: .confirm)
                            .padding(14)
                            .background(PigeonTheme.cardBackground)
                            .clipShape(RoundedRectangle(cornerRadius: 12))
                            .transition(.opacity.combined(with: .move(edge: .top)))
                        
                        if !confirmPassword.isEmpty && !passwordsMatch {
                            Text("Passwords don't match")
                                .font(PigeonTheme.captionFont)
                                .foregroundStyle(PigeonTheme.destructive)
                                .frame(maxWidth: .infinity, alignment: .leading)
                        }

                        // Account privacy toggle
                        HStack {
                            VStack(alignment: .leading, spacing: 4) {
                                Text("Private Account")
                                    .font(PigeonTheme.subheadlineFont)
                                    .foregroundStyle(PigeonTheme.primaryText)
                                Text(isPrivateAccount
                                     ? "Only friends can see your sessions"
                                     : "Anyone can see your sessions in the feed")
                                    .font(PigeonTheme.smallFont)
                                    .foregroundStyle(PigeonTheme.tertiaryText)
                            }
                            Spacer()
                            Toggle("", isOn: $isPrivateAccount)
                                .labelsHidden()
                                .tint(PigeonTheme.accent)
                        }
                        .padding(14)
                        .background(PigeonTheme.cardBackground)
                        .clipShape(RoundedRectangle(cornerRadius: 12))
                    }
                }
                .padding(.horizontal, 24)

                // Primary action button
                if isSignUpMode {
                    Button {
                        Haptics.medium()
                        focusedField = nil
                        Task { await handleEmailSignUp() }
                    } label: {
                        HStack(spacing: 12) {
                            if isSigningIn {
                                ProgressView()
                                    .tint(PigeonTheme.accentText)
                            }
                            Text("Create Account")
                                .font(PigeonTheme.subheadlineFont)
                        }
                        .foregroundStyle(PigeonTheme.accentText)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 14)
                        .background(canSignUp ? PigeonTheme.accent : PigeonTheme.elevated)
                        .clipShape(RoundedRectangle(cornerRadius: 12))
                    }
                    .disabled(!canSignUp)
                    .padding(.horizontal, 24)
                } else {
                    Button {
                        Haptics.medium()
                        focusedField = nil
                        Task { await handleEmailSignIn() }
                    } label: {
                        HStack(spacing: 12) {
                            if isSigningIn {
                                ProgressView()
                                    .tint(PigeonTheme.accentText)
                            } else {
                                Image(systemName: "envelope.fill")
                                    .font(.system(size: 18))
                            }
                            Text("Sign In")
                                .font(PigeonTheme.subheadlineFont)
                        }
                        .foregroundStyle(PigeonTheme.accentText)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 14)
                        .background(
                            (email.isEmpty || password.isEmpty || isSigningIn)
                            ? PigeonTheme.elevated
                            : PigeonTheme.accent
                        )
                        .clipShape(RoundedRectangle(cornerRadius: 12))
                    }
                    .disabled(email.isEmpty || password.isEmpty || isSigningIn)
                    .padding(.horizontal, 24)
                }
                
                // Divider
                HStack {
                    Rectangle()
                        .fill(PigeonTheme.separator)
                        .frame(height: 1)
                    Text("or")
                        .font(PigeonTheme.captionFont)
                        .foregroundStyle(PigeonTheme.tertiaryText)
                    Rectangle()
                        .fill(PigeonTheme.separator)
                        .frame(height: 1)
                }
                .padding(.horizontal, 24)
                
                // Google button
                Button {
                    Haptics.medium()
                    focusedField = nil
                    if isSignUpMode {
                        Task { await handleGoogleSignUp() }
                    } else {
                        Task { await handleGoogleSignIn() }
                    }
                } label: {
                    HStack(spacing: 12) {
                        GoogleGLogo(size: 20)
                        Text(isSignUpMode ? "Sign up with Google" : "Sign in with Google")
                            .font(PigeonTheme.subheadlineFont)
                    }
                    .foregroundStyle(PigeonTheme.primaryText)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 14)
                    .background(PigeonTheme.cardBackground)
                    .clipShape(RoundedRectangle(cornerRadius: 12))
                    .overlay(
                        RoundedRectangle(cornerRadius: 12)
                            .strokeBorder(PigeonTheme.separator, lineWidth: 1)
                    )
                }
                .disabled(isSigningIn)
                .padding(.horizontal, 24)
                
                if let signInError {
                    Text(signInError)
                        .font(PigeonTheme.captionFont)
                        .foregroundStyle(PigeonTheme.destructive)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 24)
                }
                
                if signUpSuccess {
                    VStack(spacing: 8) {
                        Image(systemName: "checkmark.circle.fill")
                            .font(.system(size: 32))
                            .foregroundStyle(.green)
                        Text("Account created! You're all set.")
                            .font(PigeonTheme.bodyFont)
                            .foregroundStyle(PigeonTheme.primaryText)
                            .multilineTextAlignment(.center)
                    }
                    .padding(16)
                    .background(PigeonTheme.cardBackground)
                    .clipShape(RoundedRectangle(cornerRadius: 12))
                    .padding(.horizontal, 24)
                }
                
                // Page indicator dots (inline on page 3)
                HStack(spacing: 8) {
                    ForEach(0..<4, id: \.self) { index in
                        RoundedRectangle(cornerRadius: 3)
                            .fill(index == currentPage ? PigeonTheme.accent : PigeonTheme.elevated)
                            .frame(width: index == currentPage ? 24 : 8, height: 8)
                    }
                }
                .padding(.top, 8)
                
                Spacer().frame(height: 40)
            }
            .padding(.bottom, focusedField != nil ? 300 : 0)
            .animation(.easeInOut(duration: 0.25), value: focusedField)
        }
        .scrollDismissesKeyboard(.interactively)
        .scrollIndicators(.hidden)
        .padding(.horizontal, 8)
        .sheet(isPresented: $showGoogleProfileSetup) {
            GoogleProfileSetupView()
        }
    }
    
    // MARK: - Sign In
    
    @MainActor
    private func handleEmailSignIn() async {
        isSigningIn = true
        signInError = nil
        do {
            try await AuthService.shared.signInWithEmail(email: email, password: password)
            createLocalUserIfNeeded()
            // Don't call onComplete() here — ContentView's onChange(of: authService.isSignedIn)
            // handles dismissing onboarding when sign-in succeeds.
        } catch {
            signInError = error.localizedDescription
        }
        isSigningIn = false
    }
    
    @MainActor
    private func handleGoogleSignIn() async {
        isSigningIn = true
        signInError = nil
        do {
            try await AuthService.shared.signInWithGoogle()
            createLocalUserIfNeeded()
        } catch {
            signInError = error.localizedDescription
        }
        isSigningIn = false
    }
    
    @MainActor
    private func handleGoogleSignUp() async {
        isSigningIn = true
        signInError = nil
        do {
            try await AuthService.shared.signInWithGoogle()
            createLocalUserIfNeeded()
            // Show profile setup so the user can set display name + photo
            showGoogleProfileSetup = true
        } catch {
            signInError = error.localizedDescription
        }
        isSigningIn = false
    }
    
    @MainActor
    private func handleEmailSignUp() async {
        isSigningIn = true
        signInError = nil
        signUpSuccess = false
        do {
            try await AuthService.shared.signUpWithEmail(
                email: email,
                password: password,
                displayName: displayName
            )
            
            // Auto sign-in after sign-up
            if !AuthService.shared.isSignedIn {
                try await AuthService.shared.signInWithEmail(email: email, password: password)
            }
            createLocalUserIfNeeded()
            
            // Claim the username
            if !username.isEmpty {
                let uid = AuthService.shared.currentUserID
                let claimed = try await SupabaseService.shared.claimUsername(username, forUser: uid)
                if claimed {
                    let descriptor = FetchDescriptor<UserProfile>(predicate: #Predicate { $0.firebaseUID == uid })
                    if let profile = try? modelContext.fetch(descriptor).first {
                        profile.username = username.lowercased()
                    }
                }
            }
        } catch {
            signInError = error.localizedDescription
        }
        isSigningIn = false
    }
    
    
    private func createLocalUserIfNeeded() {
        let uid = AuthService.shared.currentUserID
        guard !uid.isEmpty else { return }
        
        // Check if we already have a local profile for this user
        let descriptor = FetchDescriptor<UserProfile>(predicate: #Predicate { $0.firebaseUID == uid })
        if let existing = try? modelContext.fetch(descriptor).first {
            // Update display name / email if changed from Supabase user metadata
            if let user = AuthService.shared.currentUser {
                if let name = user.userMetadata["full_name"]?.stringValue, !name.isEmpty {
                    existing.displayName = name
                }
                if let email = user.email, !email.isEmpty {
                    existing.email = email
                }
                existing.avatarURL = user.userMetadata["avatar_url"]?.stringValue
            }
            return
        }
        
        // Create a minimal local profile — syncFromCloud() will merge cloud
        // data (stats, friends, timelapses) on top of this momentarily.
        let supabaseUser = AuthService.shared.currentUser
        let profile = UserProfile(
            displayName: supabaseUser?.userMetadata["full_name"]?.stringValue ?? "Student",
            email: supabaseUser?.email ?? "",
            firebaseUID: uid,
            avatarURL: supabaseUser?.userMetadata["avatar_url"]?.stringValue,
            bio: "",
            isPrivate: isPrivateAccount
        )
        modelContext.insert(profile)
    }
}

// MARK: - Sign Up View

struct SignUpView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @State private var displayName = ""
    @State private var username = ""
    @State private var usernameAvailable: Bool? = nil
    @State private var isCheckingUsername = false
    @State private var usernameCheckTask: Task<Void, Never>?
    @State private var email = ""
    @State private var password = ""
    @State private var confirmPassword = ""
    @State private var isSigningUp = false
    @State private var signUpError: String?
    @State private var signUpSuccess = false
    @State private var isPrivateAccount = true
    @FocusState private var focusedField: Field?
    let onComplete: () -> Void

    private enum Field {
        case name, username, email, password, confirm
    }
    
    private var passwordsMatch: Bool {
        !password.isEmpty && password == confirmPassword
    }
    
    private var canSubmit: Bool {
        !displayName.isEmpty && !email.isEmpty && password.count >= 6 && passwordsMatch && !isSigningUp
        && username.count >= 3 && usernameAvailable == true
    }
    
    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 24) {
                    // Header
                    VStack(spacing: 8) {
                        PigeonIcon(size: 80, color: PigeonTheme.primaryText)
                        
                        Text("create an account")
                            .font(PigeonTheme.titleFont)
                            .foregroundStyle(PigeonTheme.primaryText)
                        
                        Text("so your study sessions\nfollow you everywhere")
                            .font(PigeonTheme.bodyFont)
                            .foregroundStyle(PigeonTheme.secondaryText)
                            .multilineTextAlignment(.center)
                    }
                    .padding(.top, 16)
                    
                    // Form fields
                    VStack(spacing: 12) {
                        TextField("Display Name", text: $displayName)
                            .font(PigeonTheme.bodyFont)
                            .foregroundStyle(PigeonTheme.primaryText)
                            .textContentType(.init(rawValue: ""))
                            .focused($focusedField, equals: .name)
                            .padding(14)
                            .background(PigeonTheme.cardBackground)
                            .clipShape(RoundedRectangle(cornerRadius: 12))
                        
                        // Username field
                        HStack(spacing: 4) {
                            Text("@")
                                .font(PigeonTheme.bodyFont)
                                .foregroundStyle(PigeonTheme.tertiaryText)
                            TextField("username", text: $username)
                                .font(PigeonTheme.bodyFont)
                                .foregroundStyle(PigeonTheme.primaryText)
                                .textInputAutocapitalization(.never)
                                .autocorrectionDisabled()
                                .focused($focusedField, equals: .username)
                                .onChange(of: username) { _, newValue in
                                    let sanitized = newValue.lowercased().filter { $0.isLetter || $0.isNumber || $0 == "_" }
                                    if sanitized != newValue { username = sanitized }
                                    usernameAvailable = nil
                                    usernameCheckTask?.cancel()
                                    guard sanitized.count >= 3 else { return }
                                    usernameCheckTask = Task {
                                        isCheckingUsername = true
                                        try? await Task.sleep(for: .milliseconds(400))
                                        guard !Task.isCancelled else { return }
                                        usernameAvailable = try? await SupabaseService.shared.isUsernameAvailable(sanitized)
                                        isCheckingUsername = false
                                    }
                                }
                        }
                        .padding(14)
                        .background(PigeonTheme.cardBackground)
                        .clipShape(RoundedRectangle(cornerRadius: 12))
                        .overlay(
                            RoundedRectangle(cornerRadius: 12)
                                .strokeBorder(
                                    usernameAvailable == true ? Color.green.opacity(0.5) :
                                    usernameAvailable == false ? PigeonTheme.destructive.opacity(0.5) :
                                    Color.clear,
                                    lineWidth: 1.5
                                )
                        )
                        
                        if isCheckingUsername {
                            HStack(spacing: 6) {
                                ProgressView().scaleEffect(0.7)
                                Text("Checking...")
                                    .font(PigeonTheme.captionFont)
                                    .foregroundStyle(PigeonTheme.tertiaryText)
                            }
                            .frame(maxWidth: .infinity, alignment: .leading)
                        } else if let available = usernameAvailable {
                            Text(available ? "Username available" : "Username taken")
                                .font(PigeonTheme.captionFont)
                                .foregroundStyle(available ? .green : PigeonTheme.destructive)
                                .frame(maxWidth: .infinity, alignment: .leading)
                        }
                        
                        TextField("Email", text: $email)
                            .font(PigeonTheme.bodyFont)
                            .foregroundStyle(PigeonTheme.primaryText)
                            .keyboardType(.emailAddress)
                            .textContentType(.init(rawValue: ""))
                            .textInputAutocapitalization(.never)
                            .autocorrectionDisabled()
                            .focused($focusedField, equals: .email)
                            .padding(14)
                            .background(PigeonTheme.cardBackground)
                            .clipShape(RoundedRectangle(cornerRadius: 12))
                        
                        SecureField("Password (min 6 characters)", text: $password)
                            .font(PigeonTheme.bodyFont)
                            .foregroundStyle(PigeonTheme.primaryText)
                            .textContentType(.init(rawValue: ""))
                            .focused($focusedField, equals: .password)
                            .padding(14)
                            .background(PigeonTheme.cardBackground)
                            .clipShape(RoundedRectangle(cornerRadius: 12))
                        
                        SecureField("Confirm Password", text: $confirmPassword)
                            .font(PigeonTheme.bodyFont)
                            .foregroundStyle(PigeonTheme.primaryText)
                            .textContentType(.init(rawValue: ""))
                            .focused($focusedField, equals: .confirm)
                            .padding(14)
                            .background(PigeonTheme.cardBackground)
                            .clipShape(RoundedRectangle(cornerRadius: 12))
                        
                        // Password mismatch indicator
                        if !confirmPassword.isEmpty && !passwordsMatch {
                            Text("Passwords don't match")
                                .font(PigeonTheme.captionFont)
                                .foregroundStyle(PigeonTheme.destructive)
                                .frame(maxWidth: .infinity, alignment: .leading)
                        }

                        // Account privacy toggle
                        HStack {
                            VStack(alignment: .leading, spacing: 4) {
                                Text("Private Account")
                                    .font(PigeonTheme.subheadlineFont)
                                    .foregroundStyle(PigeonTheme.primaryText)
                                Text(isPrivateAccount
                                     ? "Only friends can see your sessions"
                                     : "Anyone can see your sessions in the feed")
                                    .font(PigeonTheme.smallFont)
                                    .foregroundStyle(PigeonTheme.tertiaryText)
                            }
                            Spacer()
                            Toggle("", isOn: $isPrivateAccount)
                                .labelsHidden()
                                .tint(PigeonTheme.accent)
                        }
                        .padding(14)
                        .background(PigeonTheme.cardBackground)
                        .clipShape(RoundedRectangle(cornerRadius: 12))
                    }
                    .padding(.horizontal, 24)

                    // Sign up button
                    Button {
                        focusedField = nil
                        Task { await handleSignUp() }
                    } label: {
                        HStack(spacing: 12) {
                            if isSigningUp {
                                ProgressView()
                                    .tint(PigeonTheme.accentText)
                            }
                            Text("Create Account")
                                .font(PigeonTheme.subheadlineFont)
                        }
                        .foregroundStyle(PigeonTheme.accentText)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 16)
                        .background(canSubmit ? PigeonTheme.accent : PigeonTheme.elevated)
                        .clipShape(RoundedRectangle(cornerRadius: 14))
                    }
                    .disabled(!canSubmit)
                    .padding(.horizontal, 24)
                    
                    if let signUpError {
                        Text(signUpError)
                            .font(PigeonTheme.captionFont)
                            .foregroundStyle(PigeonTheme.destructive)
                            .multilineTextAlignment(.center)
                            .padding(.horizontal, 24)
                    }
                    
                    if signUpSuccess {
                        VStack(spacing: 8) {
                            Image(systemName: "checkmark.circle.fill")
                                .font(.system(size: 32))
                                .foregroundStyle(.green)
                            Text("Account created! You're all set.")
                                .font(PigeonTheme.bodyFont)
                                .foregroundStyle(PigeonTheme.primaryText)
                                .multilineTextAlignment(.center)
                        }
                        .padding(16)
                        .background(PigeonTheme.cardBackground)
                        .clipShape(RoundedRectangle(cornerRadius: 12))
                        .padding(.horizontal, 24)
                    }
                }
                .padding(.bottom, 32)
            }
            .background(PigeonTheme.background)
            .onTapGesture {
                focusedField = nil
            }
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                        .foregroundStyle(PigeonTheme.secondaryText)
                        .font(PigeonTheme.bodyFont)
                }
            }
            .toolbarBackground(PigeonTheme.background, for: .navigationBar)
            .toolbarBackground(.visible, for: .navigationBar)
        }
        .presentationBackground(PigeonTheme.background)
    }
    
    @MainActor
    private func handleSignUp() async {
        isSigningUp = true
        signUpError = nil
        signUpSuccess = false
        do {
            try await AuthService.shared.signUpWithEmail(
                email: email,
                password: password,
                displayName: displayName
            )
            
            // Auto sign-in after sign-up
            if !AuthService.shared.isSignedIn {
                try await AuthService.shared.signInWithEmail(email: email, password: password)
            }
            createLocalUserIfNeeded()
            
            // Claim the username
            if !username.isEmpty {
                let uid = AuthService.shared.currentUserID
                let claimed = try await SupabaseService.shared.claimUsername(username, forUser: uid)
                if claimed {
                    let descriptor = FetchDescriptor<UserProfile>(predicate: #Predicate { $0.firebaseUID == uid })
                    if let profile = try? modelContext.fetch(descriptor).first {
                        profile.username = username.lowercased()
                    }
                }
            }
            
            dismiss()
            onComplete()
        } catch {
            signUpError = error.localizedDescription
        }
        isSigningUp = false
    }
    
    private func createLocalUserIfNeeded() {
        let uid = AuthService.shared.currentUserID
        guard !uid.isEmpty else { return }
        
        let descriptor = FetchDescriptor<UserProfile>(predicate: #Predicate { $0.firebaseUID == uid })
        if (try? modelContext.fetch(descriptor).first) != nil {
            return
        }
        
        let profile = UserProfile(
            displayName: displayName,
            email: email,
            firebaseUID: uid,
            username: username.lowercased(),
            avatarURL: nil,
            bio: "",
            isPrivate: isPrivateAccount
        )
        modelContext.insert(profile)
    }
}

// MARK: - Google G Logo

/// Google "G" logo traced from the official SVG (viewBox 0 0 48 48), scaled to any size.
struct GoogleGLogo: View {
    var size: CGFloat = 20
    
    var body: some View {
        Image("GoogleLogo")
            .resizable()
            .scaledToFit()
            .frame(width: size, height: size)
    }
}

// MARK: - Google Profile Setup (after Google Sign-Up)

struct GoogleProfileSetupView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @Query private var users: [UserProfile]
    @State private var editedName = ""
    @State private var username = ""
    @State private var usernameAvailable: Bool? = nil
    @State private var isCheckingUsername = false
    @State private var usernameCheckTask: Task<Void, Never>?
    @State private var isSaving = false
    @State private var isPrivateAccount = true

    private var currentUser: UserProfile? {
        let uid = AuthService.shared.currentUserID
        return users.first { $0.firebaseUID == uid }
    }
    
    var body: some View {
        NavigationStack {
            VStack(spacing: 24) {
                Spacer()
                
                // Avatar
                if let currentUser {
                    avatarView(name: currentUser.displayName, size: 80, avatarURL: currentUser.avatarURL)
                }
                
                Text("welcome to pigeon")
                    .font(PigeonTheme.titleFont)
                    .foregroundStyle(PigeonTheme.primaryText)
                
                Text("set your name & username")
                    .font(PigeonTheme.bodyFont)
                    .foregroundStyle(PigeonTheme.secondaryText)
                
                VStack(spacing: 12) {
                    TextField("Display Name", text: $editedName)
                        .font(PigeonTheme.bodyFont)
                        .foregroundStyle(PigeonTheme.primaryText)
                        .textContentType(.name)
                        .autocorrectionDisabled()
                        .padding(14)
                        .background(PigeonTheme.cardBackground)
                        .clipShape(RoundedRectangle(cornerRadius: 12))
                    
                    HStack(spacing: 4) {
                        Text("@")
                            .font(PigeonTheme.bodyFont)
                            .foregroundStyle(PigeonTheme.tertiaryText)
                        TextField("username", text: $username)
                            .font(PigeonTheme.bodyFont)
                            .foregroundStyle(PigeonTheme.primaryText)
                            .textInputAutocapitalization(.never)
                            .autocorrectionDisabled()
                            .onChange(of: username) { _, newValue in
                                let sanitized = newValue.lowercased().filter { $0.isLetter || $0.isNumber || $0 == "_" }
                                if sanitized != newValue { username = sanitized }
                                usernameAvailable = nil
                                usernameCheckTask?.cancel()
                                guard sanitized.count >= 3 else { return }
                                usernameCheckTask = Task {
                                    isCheckingUsername = true
                                    try? await Task.sleep(for: .milliseconds(400))
                                    guard !Task.isCancelled else { return }
                                    usernameAvailable = try? await SupabaseService.shared.isUsernameAvailable(sanitized)
                                    isCheckingUsername = false
                                }
                            }
                    }
                    .padding(14)
                    .background(PigeonTheme.cardBackground)
                    .clipShape(RoundedRectangle(cornerRadius: 12))
                    .overlay(
                        RoundedRectangle(cornerRadius: 12)
                            .strokeBorder(
                                usernameAvailable == true ? Color.green.opacity(0.5) :
                                usernameAvailable == false ? PigeonTheme.destructive.opacity(0.5) :
                                Color.clear,
                                lineWidth: 1.5
                            )
                    )
                    
                    if isCheckingUsername {
                        HStack(spacing: 6) {
                            ProgressView().scaleEffect(0.7)
                            Text("Checking...")
                                .font(PigeonTheme.captionFont)
                                .foregroundStyle(PigeonTheme.tertiaryText)
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                    } else if let available = usernameAvailable {
                        Text(available ? "Username available" : "Username taken")
                            .font(PigeonTheme.captionFont)
                            .foregroundStyle(available ? .green : PigeonTheme.destructive)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }

                    // Account privacy toggle
                    HStack {
                        VStack(alignment: .leading, spacing: 4) {
                            Text("Private Account")
                                .font(PigeonTheme.subheadlineFont)
                                .foregroundStyle(PigeonTheme.primaryText)
                            Text(isPrivateAccount
                                 ? "Only friends can see your sessions"
                                 : "Anyone can see your sessions in the feed")
                                .font(PigeonTheme.smallFont)
                                .foregroundStyle(PigeonTheme.tertiaryText)
                        }
                        Spacer()
                        Toggle("", isOn: $isPrivateAccount)
                            .labelsHidden()
                            .tint(PigeonTheme.accent)
                    }
                    .padding(14)
                    .background(PigeonTheme.cardBackground)
                    .clipShape(RoundedRectangle(cornerRadius: 12))
                }
                .padding(.horizontal, 24)

                Button {
                    isSaving = true
                    let trimmed = editedName.trimmingCharacters(in: .whitespaces)
                    if !trimmed.isEmpty {
                        currentUser?.displayName = trimmed
                    }
                    currentUser?.isPrivate = isPrivateAccount
                    Task {
                        if username.count >= 3, usernameAvailable == true {
                            let uid = AuthService.shared.currentUserID
                            let claimed = try? await SupabaseService.shared.claimUsername(username, forUser: uid)
                            if claimed == true {
                                currentUser?.username = username.lowercased()
                            }
                        }
                        isSaving = false
                        dismiss()
                    }
                } label: {
                    HStack(spacing: 8) {
                        if isSaving { ProgressView().tint(PigeonTheme.accentText) }
                        Text("Continue")
                            .font(PigeonTheme.subheadlineFont)
                    }
                    .foregroundStyle(PigeonTheme.accentText)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 16)
                    .background(
                        (isSaving || username.count < 3 || usernameAvailable != true)
                        ? PigeonTheme.elevated : PigeonTheme.accent
                    )
                    .clipShape(RoundedRectangle(cornerRadius: 14))
                }
                .disabled(isSaving || username.count < 3 || usernameAvailable != true)
                .padding(.horizontal, 24)
                
                Spacer()
            }
            .background(PigeonTheme.background)
            .toolbar(.hidden, for: .navigationBar)
        }
        .presentationBackground(PigeonTheme.background)
        .onAppear {
            editedName = currentUser?.displayName ?? ""
        }
    }
}

#Preview {
    OnboardingView { }
        .modelContainer(for: [UserProfile.self, StudyTimelapse.self, StudyGroup.self, StudySubject.self], inMemory: true)
}

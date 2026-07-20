//
//  OnboardingView.swift
//  Factum
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
    @State private var confirmPassword = ""
    @State private var signUpSuccess = false
    @State private var showGoogleProfileSetup = false
    @FocusState private var focusedField: AuthField?
    let onComplete: () -> Void
    
    private enum AuthField {
        case name, email, password, confirm
    }
    
    var body: some View {
        ZStack {
            FactumTheme.background.ignoresSafeArea()
            
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
                                .fill(index == currentPage ? FactumTheme.accent : FactumTheme.elevated)
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
                            .font(FactumTheme.subheadlineFont)
                            .foregroundStyle(FactumTheme.accentText)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 16)
                            .background(FactumTheme.accent)
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
            
            FactumIcon(size: 120, color: FactumTheme.primaryText)
                .scaleEffect(isAnimating ? 1.0 : 0.8)
                .opacity(isAnimating ? 1.0 : 0)
                .animation(.spring(response: 0.8, dampingFraction: 0.6), value: isAnimating)
            
            Text("factum")
                .font(.system(size: 38, weight: .light, design: .serif))
                .foregroundStyle(FactumTheme.primaryText)
                .tracking(4)
            
            Text("a quiet place to study")
                .font(FactumTheme.bodyFont)
                .foregroundStyle(FactumTheme.secondaryText)
            
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
                    .fill(FactumTheme.cardBackground)
                    .frame(width: 200, height: 160)
                
                VStack(spacing: 12) {
                    Image(systemName: "timelapse")
                        .font(.system(size: 48))
                        .foregroundStyle(FactumTheme.accent)
                    
                    Text("2h 15m")
                        .font(FactumTheme.font(20, weight: .bold))
                        .foregroundStyle(FactumTheme.primaryText)
                }
            }
            
            Text("record the work")
                .font(FactumTheme.titleFont)
                .foregroundStyle(FactumTheme.primaryText)
            
            Text("your study sessions become\nshort timelapses — proof\nthat the hours happened")
                .font(FactumTheme.bodyFont)
                .foregroundStyle(FactumTheme.secondaryText)
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
                // Stacked avatar bubbles
                HStack(spacing: -12) {
                    ForEach(["S", "J", "P", "A"], id: \.self) { initial in
                        Circle()
                            .fill(FactumTheme.elevated)
                            .frame(width: 52, height: 52)
                            .overlay(
                                Text(initial)
                                    .font(FactumTheme.font(20, weight: .semibold))
                                    .foregroundStyle(FactumTheme.primaryText)
                            )
                            .overlay(
                                Circle().strokeBorder(FactumTheme.background, lineWidth: 3)
                            )
                    }
                }
            }
            
            Text("study together")
                .font(FactumTheme.titleFont)
                .foregroundStyle(FactumTheme.primaryText)
            
            Text("see what your friends are\nworking on — it's easier to\nshow up when others do too")
                .font(FactumTheme.bodyFont)
                .foregroundStyle(FactumTheme.secondaryText)
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
    }
    
    private var getStartedPage: some View {
        ScrollView {
            VStack(spacing: 20) {
                FactumIcon(size: 60, color: FactumTheme.primaryText)
                    .padding(.top, 24)
                
                Text(isSignUpMode ? "create an account" : "ready when you are")
                    .font(FactumTheme.titleFont)
                    .foregroundStyle(FactumTheme.primaryText)
                
                Text(isSignUpMode ? "so your study sessions follow you" : "sign in to keep your work safe")
                    .font(FactumTheme.bodyFont)
                    .foregroundStyle(FactumTheme.secondaryText)
                
                // Sign In / Sign Up toggle
                HStack(spacing: 0) {
                    Button {
                        withAnimation(.easeInOut(duration: 0.25)) {
                            isSignUpMode = false
                            signInError = nil
                        }
                    } label: {
                        Text("Sign In")
                            .font(FactumTheme.subheadlineFont)
                            .foregroundStyle(isSignUpMode ? FactumTheme.secondaryText : FactumTheme.primaryText)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 10)
                            .background(isSignUpMode ? Color.clear : FactumTheme.accent)
                            .clipShape(RoundedRectangle(cornerRadius: 10))
                    }
                    
                    Button {
                        withAnimation(.easeInOut(duration: 0.25)) {
                            isSignUpMode = true
                            signInError = nil
                        }
                    } label: {
                        Text("Sign Up")
                            .font(FactumTheme.subheadlineFont)
                            .foregroundStyle(isSignUpMode ? FactumTheme.primaryText : FactumTheme.secondaryText)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 10)
                            .background(isSignUpMode ? FactumTheme.accent : Color.clear)
                            .clipShape(RoundedRectangle(cornerRadius: 10))
                    }
                }
                .padding(4)
                .background(FactumTheme.cardBackground)
                .clipShape(RoundedRectangle(cornerRadius: 12))
                .padding(.horizontal, 24)
                
                // Form fields
                VStack(spacing: 12) {
                    if isSignUpMode {
                        TextField("Display Name", text: $displayName)
                            .font(FactumTheme.bodyFont)
                            .foregroundStyle(FactumTheme.primaryText)
                            .textContentType(.name)
                            .autocorrectionDisabled()
                            .focused($focusedField, equals: .name)
                            .padding(14)
                            .background(FactumTheme.cardBackground)
                            .clipShape(RoundedRectangle(cornerRadius: 12))
                            .transition(.opacity.combined(with: .move(edge: .top)))
                    }
                    
                    TextField("Email", text: $email)
                        .font(FactumTheme.bodyFont)
                        .foregroundStyle(FactumTheme.primaryText)
                        .keyboardType(.emailAddress)
                        .textContentType(.emailAddress)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .focused($focusedField, equals: .email)
                        .padding(14)
                        .background(FactumTheme.cardBackground)
                        .clipShape(RoundedRectangle(cornerRadius: 12))
                    
                    SecureField(isSignUpMode ? "Password (min 6 characters)" : "Password", text: $password)
                        .font(FactumTheme.bodyFont)
                        .foregroundStyle(FactumTheme.primaryText)
                        .textContentType(isSignUpMode ? .newPassword : .password)
                        .autocorrectionDisabled()
                        .focused($focusedField, equals: .password)
                        .padding(14)
                        .background(FactumTheme.cardBackground)
                        .clipShape(RoundedRectangle(cornerRadius: 12))
                    
                    if isSignUpMode {
                        SecureField("Confirm Password", text: $confirmPassword)
                            .font(FactumTheme.bodyFont)
                            .foregroundStyle(FactumTheme.primaryText)
                            .textContentType(.newPassword)
                            .autocorrectionDisabled()
                            .focused($focusedField, equals: .confirm)
                            .padding(14)
                            .background(FactumTheme.cardBackground)
                            .clipShape(RoundedRectangle(cornerRadius: 12))
                            .transition(.opacity.combined(with: .move(edge: .top)))
                        
                        if !confirmPassword.isEmpty && !passwordsMatch {
                            Text("Passwords don't match")
                                .font(FactumTheme.captionFont)
                                .foregroundStyle(FactumTheme.destructive)
                                .frame(maxWidth: .infinity, alignment: .leading)
                        }
                    }
                }
                .padding(.horizontal, 24)
                
                // Primary action button
                if isSignUpMode {
                    Button {
                        focusedField = nil
                        Task { await handleEmailSignUp() }
                    } label: {
                        HStack(spacing: 12) {
                            if isSigningIn {
                                ProgressView()
                                    .tint(FactumTheme.accentText)
                            }
                            Text("Create Account")
                                .font(FactumTheme.subheadlineFont)
                        }
                        .foregroundStyle(FactumTheme.accentText)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 14)
                        .background(canSignUp ? FactumTheme.accent : FactumTheme.elevated)
                        .clipShape(RoundedRectangle(cornerRadius: 12))
                    }
                    .disabled(!canSignUp)
                    .padding(.horizontal, 24)
                } else {
                    Button {
                        focusedField = nil
                        Task { await handleEmailSignIn() }
                    } label: {
                        HStack(spacing: 12) {
                            if isSigningIn {
                                ProgressView()
                                    .tint(FactumTheme.accentText)
                            } else {
                                Image(systemName: "envelope.fill")
                                    .font(.system(size: 18))
                            }
                            Text("Sign In")
                                .font(FactumTheme.subheadlineFont)
                        }
                        .foregroundStyle(FactumTheme.accentText)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 14)
                        .background(
                            (email.isEmpty || password.isEmpty || isSigningIn)
                            ? FactumTheme.elevated
                            : FactumTheme.accent
                        )
                        .clipShape(RoundedRectangle(cornerRadius: 12))
                    }
                    .disabled(email.isEmpty || password.isEmpty || isSigningIn)
                    .padding(.horizontal, 24)
                }
                
                // Divider
                HStack {
                    Rectangle()
                        .fill(FactumTheme.separator)
                        .frame(height: 1)
                    Text("or")
                        .font(FactumTheme.captionFont)
                        .foregroundStyle(FactumTheme.tertiaryText)
                    Rectangle()
                        .fill(FactumTheme.separator)
                        .frame(height: 1)
                }
                .padding(.horizontal, 24)
                
                // Google button
                Button {
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
                            .font(FactumTheme.subheadlineFont)
                    }
                    .foregroundStyle(FactumTheme.primaryText)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 14)
                    .background(FactumTheme.cardBackground)
                    .clipShape(RoundedRectangle(cornerRadius: 12))
                    .overlay(
                        RoundedRectangle(cornerRadius: 12)
                            .strokeBorder(FactumTheme.separator, lineWidth: 1)
                    )
                }
                .disabled(isSigningIn)
                .padding(.horizontal, 24)
                
                if let signInError {
                    Text(signInError)
                        .font(FactumTheme.captionFont)
                        .foregroundStyle(FactumTheme.destructive)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 24)
                }
                
                if signUpSuccess {
                    VStack(spacing: 8) {
                        Image(systemName: "checkmark.circle.fill")
                            .font(.system(size: 32))
                            .foregroundStyle(.green)
                        Text("Account created! Check your email to confirm, then sign in.")
                            .font(FactumTheme.bodyFont)
                            .foregroundStyle(FactumTheme.primaryText)
                            .multilineTextAlignment(.center)
                    }
                    .padding(16)
                    .background(FactumTheme.cardBackground)
                    .clipShape(RoundedRectangle(cornerRadius: 12))
                    .padding(.horizontal, 24)
                }
                
                // Page indicator dots (inline on page 3)
                HStack(spacing: 8) {
                    ForEach(0..<4, id: \.self) { index in
                        RoundedRectangle(cornerRadius: 3)
                            .fill(index == currentPage ? FactumTheme.accent : FactumTheme.elevated)
                            .frame(width: index == currentPage ? 24 : 8, height: 8)
                    }
                }
                .padding(.top, 8)
                
                Spacer().frame(height: 40)
            }
            .padding(.bottom, 300)
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
            
            // If Supabase auto-confirms (no email verification required),
            // the user is now signed in. Create the local profile and proceed.
            if AuthService.shared.isSignedIn {
                createLocalUserIfNeeded()
                // ContentView's onChange handles dismissal
            } else {
                // Email confirmation required — show success message
                signUpSuccess = true
                // Switch back to sign-in mode so user can sign in after confirming
                withAnimation(.easeInOut(duration: 0.25)) {
                    isSignUpMode = false
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
            bio: ""
        )
        modelContext.insert(profile)
    }
}

// MARK: - Sign Up View

struct SignUpView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @State private var displayName = ""
    @State private var email = ""
    @State private var password = ""
    @State private var confirmPassword = ""
    @State private var isSigningUp = false
    @State private var signUpError: String?
    @State private var signUpSuccess = false
    @FocusState private var focusedField: Field?
    let onComplete: () -> Void
    
    private enum Field {
        case name, email, password, confirm
    }
    
    private var passwordsMatch: Bool {
        !password.isEmpty && password == confirmPassword
    }
    
    private var canSubmit: Bool {
        !displayName.isEmpty && !email.isEmpty && password.count >= 6 && passwordsMatch && !isSigningUp
    }
    
    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 24) {
                    // Header
                    VStack(spacing: 8) {
                        FactumIcon(size: 60, color: FactumTheme.primaryText)
                        
                        Text("create an account")
                            .font(FactumTheme.titleFont)
                            .foregroundStyle(FactumTheme.primaryText)
                        
                        Text("so your study sessions\nfollow you everywhere")
                            .font(FactumTheme.bodyFont)
                            .foregroundStyle(FactumTheme.secondaryText)
                            .multilineTextAlignment(.center)
                    }
                    .padding(.top, 16)
                    
                    // Form fields
                    VStack(spacing: 12) {
                        TextField("Display Name", text: $displayName)
                            .font(FactumTheme.bodyFont)
                            .foregroundStyle(FactumTheme.primaryText)
                            .textContentType(.init(rawValue: ""))
                            .focused($focusedField, equals: .name)
                            .padding(14)
                            .background(FactumTheme.cardBackground)
                            .clipShape(RoundedRectangle(cornerRadius: 12))
                        
                        TextField("Email", text: $email)
                            .font(FactumTheme.bodyFont)
                            .foregroundStyle(FactumTheme.primaryText)
                            .keyboardType(.emailAddress)
                            .textContentType(.init(rawValue: ""))
                            .textInputAutocapitalization(.never)
                            .autocorrectionDisabled()
                            .focused($focusedField, equals: .email)
                            .padding(14)
                            .background(FactumTheme.cardBackground)
                            .clipShape(RoundedRectangle(cornerRadius: 12))
                        
                        SecureField("Password (min 6 characters)", text: $password)
                            .font(FactumTheme.bodyFont)
                            .foregroundStyle(FactumTheme.primaryText)
                            .textContentType(.init(rawValue: ""))
                            .focused($focusedField, equals: .password)
                            .padding(14)
                            .background(FactumTheme.cardBackground)
                            .clipShape(RoundedRectangle(cornerRadius: 12))
                        
                        SecureField("Confirm Password", text: $confirmPassword)
                            .font(FactumTheme.bodyFont)
                            .foregroundStyle(FactumTheme.primaryText)
                            .textContentType(.init(rawValue: ""))
                            .focused($focusedField, equals: .confirm)
                            .padding(14)
                            .background(FactumTheme.cardBackground)
                            .clipShape(RoundedRectangle(cornerRadius: 12))
                        
                        // Password mismatch indicator
                        if !confirmPassword.isEmpty && !passwordsMatch {
                            Text("Passwords don't match")
                                .font(FactumTheme.captionFont)
                                .foregroundStyle(FactumTheme.destructive)
                                .frame(maxWidth: .infinity, alignment: .leading)
                        }
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
                                    .tint(FactumTheme.accentText)
                            }
                            Text("Create Account")
                                .font(FactumTheme.subheadlineFont)
                        }
                        .foregroundStyle(FactumTheme.accentText)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 16)
                        .background(canSubmit ? FactumTheme.accent : FactumTheme.elevated)
                        .clipShape(RoundedRectangle(cornerRadius: 14))
                    }
                    .disabled(!canSubmit)
                    .padding(.horizontal, 24)
                    
                    if let signUpError {
                        Text(signUpError)
                            .font(FactumTheme.captionFont)
                            .foregroundStyle(FactumTheme.destructive)
                            .multilineTextAlignment(.center)
                            .padding(.horizontal, 24)
                    }
                    
                    if signUpSuccess {
                        VStack(spacing: 8) {
                            Image(systemName: "checkmark.circle.fill")
                                .font(.system(size: 32))
                                .foregroundStyle(.green)
                            Text("Account created! Check your email to confirm, then sign in.")
                                .font(FactumTheme.bodyFont)
                                .foregroundStyle(FactumTheme.primaryText)
                                .multilineTextAlignment(.center)
                        }
                        .padding(16)
                        .background(FactumTheme.cardBackground)
                        .clipShape(RoundedRectangle(cornerRadius: 12))
                        .padding(.horizontal, 24)
                    }
                }
                .padding(.bottom, 32)
            }
            .background(FactumTheme.background)
            .onTapGesture {
                focusedField = nil
            }
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                        .foregroundStyle(FactumTheme.secondaryText)
                        .font(FactumTheme.bodyFont)
                }
            }
            .toolbarBackground(FactumTheme.background, for: .navigationBar)
            .toolbarBackground(.visible, for: .navigationBar)
        }
        .presentationBackground(FactumTheme.background)
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
            
            // If Supabase auto-confirms (no email verification required),
            // the user is now signed in. Create the local profile and proceed.
            if AuthService.shared.isSignedIn {
                createLocalUserIfNeeded()
                dismiss()
                onComplete()
            } else {
                // Email confirmation required — show success message
                signUpSuccess = true
            }
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
            avatarURL: nil,
            bio: ""
        )
        modelContext.insert(profile)
    }
}

// MARK: - Google G Logo

/// Google "G" logo traced from the official SVG (viewBox 0 0 48 48), scaled to any size.
struct GoogleGLogo: View {
    var size: CGFloat = 20
    
    private let blue  = Color(red: 66/255,  green: 133/255, blue: 244/255)
    private let red   = Color(red: 219/255, green: 68/255,  blue: 55/255)
    private let yellow = Color(red: 244/255, green: 180/255, blue: 0/255)
    private let green = Color(red: 15/255,  green: 157/255, blue: 88/255)
    
    var body: some View {
        Canvas { ctx, sz in
            let s = sz.width / 48  // scale factor from 48×48 viewBox
            
            // Blue: full G outline (fills everything, other colors overlay on top)
            var bp = Path()
            bp.move(to: pt(43.611, 20.083, s))
            bp.addLine(to: pt(43.611, 23.917, s))
            bp.addCurve(to: pt(24, 43.5, s),
                        control1: pt(43.0, 34.167, s), control2: pt(34.833, 43.5, s))
            bp.addCurve(to: pt(4.5, 24, s),
                        control1: pt(13.167, 43.5, s), control2: pt(4.5, 34.833, s))
            bp.addCurve(to: pt(24, 4.5, s),
                        control1: pt(4.5, 13.167, s), control2: pt(13.167, 4.5, s))
            bp.addCurve(to: pt(34.833, 9.167, s),
                        control1: pt(29.5, 4.5, s), control2: pt(32.667, 6.083, s))
            bp.addLine(to: pt(29.917, 14.083, s))
            bp.addCurve(to: pt(24, 11.5, s),
                        control1: pt(28.333, 12.5, s), control2: pt(26.25, 11.5, s))
            bp.addCurve(to: pt(11.5, 24, s),
                        control1: pt(17.083, 11.5, s), control2: pt(11.5, 17.083, s))
            bp.addCurve(to: pt(24, 36.5, s),
                        control1: pt(11.5, 30.917, s), control2: pt(17.083, 36.5, s))
            bp.addCurve(to: pt(35, 27.5, s),
                        control1: pt(31.417, 36.5, s), control2: pt(34.167, 32.833, s))
            bp.addLine(to: pt(24, 27.5, s))
            bp.addLine(to: pt(24, 20.083, s))
            bp.closeSubpath()
            ctx.fill(bp, with: .color(blue))
            
            // Red: top-left arc (outer + inner ring, left-top quadrant)
            var rp = Path()
            rp.move(to: pt(4.5, 24, s))
            rp.addCurve(to: pt(24, 4.5, s),
                        control1: pt(4.5, 13.167, s), control2: pt(13.167, 4.5, s))
            rp.addCurve(to: pt(34.833, 9.167, s),
                        control1: pt(29.5, 4.5, s), control2: pt(32.667, 6.083, s))
            rp.addLine(to: pt(29.917, 14.083, s))
            rp.addCurve(to: pt(24, 11.5, s),
                        control1: pt(28.333, 12.5, s), control2: pt(26.25, 11.5, s))
            rp.addCurve(to: pt(11.5, 24, s),
                        control1: pt(17.083, 11.5, s), control2: pt(11.5, 17.083, s))
            rp.closeSubpath()
            ctx.fill(rp, with: .color(red))
            
            // Yellow: bottom-left arc
            var yp = Path()
            yp.move(to: pt(4.5, 24, s))
            yp.addCurve(to: pt(24, 43.5, s),
                        control1: pt(4.5, 34.833, s), control2: pt(13.167, 43.5, s))
            yp.addLine(to: pt(24, 36.5, s))
            yp.addCurve(to: pt(11.5, 24, s),
                        control1: pt(17.083, 36.5, s), control2: pt(11.5, 30.917, s))
            yp.closeSubpath()
            ctx.fill(yp, with: .color(yellow))
            
            // Green: bottom-right arc
            var gp = Path()
            gp.move(to: pt(43.611, 23.917, s))
            gp.addCurve(to: pt(24, 43.5, s),
                        control1: pt(43.0, 34.167, s), control2: pt(34.833, 43.5, s))
            gp.addLine(to: pt(24, 36.5, s))
            gp.addCurve(to: pt(35, 27.5, s),
                        control1: pt(31.417, 36.5, s), control2: pt(34.167, 32.833, s))
            gp.addLine(to: pt(24, 27.5, s))
            gp.addLine(to: pt(24, 20.083, s))
            gp.addLine(to: pt(43.611, 20.083, s))
            gp.closeSubpath()
            ctx.fill(gp, with: .color(green))
        }
        .frame(width: size, height: size)
    }
    
    private func pt(_ x: CGFloat, _ y: CGFloat, _ s: CGFloat) -> CGPoint {
        CGPoint(x: x * s, y: y * s)
    }
}

// MARK: - Google Profile Setup (after Google Sign-Up)

struct GoogleProfileSetupView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @Query private var users: [UserProfile]
    @State private var editedName = ""
    @State private var isSaving = false
    
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
                
                Text("welcome to factum")
                    .font(FactumTheme.titleFont)
                    .foregroundStyle(FactumTheme.primaryText)
                
                Text("set your display name")
                    .font(FactumTheme.bodyFont)
                    .foregroundStyle(FactumTheme.secondaryText)
                
                TextField("Display Name", text: $editedName)
                    .font(FactumTheme.bodyFont)
                    .foregroundStyle(FactumTheme.primaryText)
                    .textContentType(.name)
                    .autocorrectionDisabled()
                    .padding(14)
                    .background(FactumTheme.cardBackground)
                    .clipShape(RoundedRectangle(cornerRadius: 12))
                    .padding(.horizontal, 24)
                
                Button {
                    let trimmed = editedName.trimmingCharacters(in: .whitespaces)
                    if !trimmed.isEmpty {
                        currentUser?.displayName = trimmed
                    }
                    dismiss()
                } label: {
                    Text("Continue")
                        .font(FactumTheme.subheadlineFont)
                        .foregroundStyle(FactumTheme.accentText)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 16)
                        .background(FactumTheme.accent)
                        .clipShape(RoundedRectangle(cornerRadius: 14))
                }
                .padding(.horizontal, 24)
                
                Button("Skip") {
                    dismiss()
                }
                .font(FactumTheme.captionFont)
                .foregroundStyle(FactumTheme.tertiaryText)
                
                Spacer()
            }
            .background(FactumTheme.background)
            .toolbar(.hidden, for: .navigationBar)
        }
        .presentationBackground(FactumTheme.background)
        .onAppear {
            editedName = currentUser?.displayName ?? ""
        }
    }
}

#Preview {
    OnboardingView { }
        .modelContainer(for: [UserProfile.self, StudyTimelapse.self, TimelapseComment.self, StudyGroup.self, StudySubject.self], inMemory: true)
}

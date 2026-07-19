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
    @State private var showSignUp = false
    @State private var email = ""
    @State private var password = ""
    @FocusState private var focusedField: AuthField?
    let onComplete: () -> Void
    
    private enum AuthField {
        case email, password
    }
    
    var body: some View {
        ZStack {
            FactumTheme.background.ignoresSafeArea()
            
            VStack(spacing: 0) {
                Spacer()
                
                // Pages
                TabView(selection: $currentPage) {
                    welcomePage.tag(0)
                    timelapsePage.tag(1)
                    socialPage.tag(2)
                    getStartedPage.tag(3)
                }
                .tabViewStyle(.page(indexDisplayMode: .never))
                
                // Page indicator
                HStack(spacing: 8) {
                    ForEach(0..<4, id: \.self) { index in
                        RoundedRectangle(cornerRadius: 3)
                            .fill(index == currentPage ? FactumTheme.accent : FactumTheme.elevated)
                            .frame(width: index == currentPage ? 24 : 8, height: 8)
                            .animation(.easeInOut(duration: 0.25), value: currentPage)
                    }
                }
                .padding(.bottom, 32)
                
                // Bottom button
                if currentPage < 3 {
                    Button {
                        withAnimation {
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
                } else {
                    Spacer().frame(height: 96)
                }
            }
        }
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
    
    private var getStartedPage: some View {
        VStack(spacing: 20) {
            Spacer()
            
            FactumIcon(size: 80, color: FactumTheme.primaryText)
            
            Text("ready when you are")
                .font(FactumTheme.titleFont)
                .foregroundStyle(FactumTheme.primaryText)
            
            Text("sign in to keep your work safe")
                .font(FactumTheme.bodyFont)
                .foregroundStyle(FactumTheme.secondaryText)
            
            // Email + password fields
            VStack(spacing: 12) {
                TextField("Email", text: $email)
                    .font(FactumTheme.bodyFont)
                    .foregroundStyle(FactumTheme.primaryText)
                    .keyboardType(.emailAddress)
                    .textContentType(.oneTimeCode)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .focused($focusedField, equals: .email)
                    .padding(14)
                    .background(FactumTheme.cardBackground)
                    .clipShape(RoundedRectangle(cornerRadius: 12))
                
                SecureField("Password", text: $password)
                    .font(FactumTheme.bodyFont)
                    .foregroundStyle(FactumTheme.primaryText)
                    .textContentType(.oneTimeCode)
                    .focused($focusedField, equals: .password)
                    .padding(14)
                    .background(FactumTheme.cardBackground)
                    .clipShape(RoundedRectangle(cornerRadius: 12))
            }
            .padding(.horizontal, 24)
            
            // Sign in with email button
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
            
            // Google Sign-In button
            Button {
                focusedField = nil
                Task { await handleGoogleSignIn() }
            } label: {
                HStack(spacing: 12) {
                    Image(systemName: "g.circle.fill")
                        .font(.system(size: 22))
                    Text("Sign in with Google")
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
            
            // Sign up link
            Button {
                showSignUp = true
            } label: {
                Text("Don't have an account? **Sign Up**")
                    .font(FactumTheme.captionFont)
                    .foregroundStyle(FactumTheme.secondaryText)
            }
            .padding(.top, 4)
            
            Spacer()
        }
        .padding(.horizontal, 8)
        .sheet(isPresented: $showSignUp) {
            SignUpView(onComplete: onComplete)
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
            // Don't call onComplete() here — ContentView's onChange(of: authService.isSignedIn)
            // handles dismissing onboarding when sign-in succeeds.
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
                            .textContentType(.oneTimeCode)
                            .focused($focusedField, equals: .name)
                            .padding(14)
                            .background(FactumTheme.cardBackground)
                            .clipShape(RoundedRectangle(cornerRadius: 12))
                        
                        TextField("Email", text: $email)
                            .font(FactumTheme.bodyFont)
                            .foregroundStyle(FactumTheme.primaryText)
                            .keyboardType(.emailAddress)
                            .textContentType(.oneTimeCode)
                            .textInputAutocapitalization(.never)
                            .autocorrectionDisabled()
                            .focused($focusedField, equals: .email)
                            .padding(14)
                            .background(FactumTheme.cardBackground)
                            .clipShape(RoundedRectangle(cornerRadius: 12))
                        
                        SecureField("Password (min 6 characters)", text: $password)
                            .font(FactumTheme.bodyFont)
                            .foregroundStyle(FactumTheme.primaryText)
                            .textContentType(.oneTimeCode)
                            .focused($focusedField, equals: .password)
                            .padding(14)
                            .background(FactumTheme.cardBackground)
                            .clipShape(RoundedRectangle(cornerRadius: 12))
                        
                        SecureField("Confirm Password", text: $confirmPassword)
                            .font(FactumTheme.bodyFont)
                            .foregroundStyle(FactumTheme.primaryText)
                            .textContentType(.oneTimeCode)
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

#Preview {
    OnboardingView { }
        .modelContainer(for: [UserProfile.self, StudyTimelapse.self, TimelapseComment.self, StudyGroup.self, StudySubject.self], inMemory: true)
}

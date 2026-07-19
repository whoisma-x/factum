//
//  SupabaseClient.swift
//  Factum
//
//  Shared Supabase client instance
//

import Foundation
import Supabase

let supabase = SupabaseClient(
    supabaseURL: URL(string: "https://ijtyoxqaaopvnxvblhdf.supabase.co")!,
    supabaseKey: "sb_publishable_6zWOMkf4_2P_ueLsrLg2-A_eKhIJg0e"
)

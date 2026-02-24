//
//  AuroraAnimations.swift
//  Motive
//
//  Aurora Design System - Animation Presets
//

import SwiftUI
import AppKit

// MARK: - Aurora Animations

extension Animation {
    // Spring animations - preferred for natural motion
    static let auroraSpring = Animation.spring(response: 0.3, dampingFraction: 0.7)
    static let auroraSpringBouncy = Animation.spring(response: 0.4, dampingFraction: 0.6)
    static let auroraSpringStiff = Animation.spring(response: 0.25, dampingFraction: 0.8)
    static let auroraSpringSnappy = Animation.spring(response: 0.15, dampingFraction: 0.9)

    // Spring-based replacements for timing animations (preferred)
    static let auroraInstant = Animation.spring(response: 0.1, dampingFraction: 0.9)
    static let auroraFast = Animation.spring(response: 0.15, dampingFraction: 0.85)
    static let auroraNormal = Animation.spring(response: 0.25, dampingFraction: 0.8)
    static let auroraSlow = Animation.spring(response: 0.4, dampingFraction: 0.75)

    // Legacy compatibility
    static let velvetSpring = auroraSpring
    static let quickSpring = auroraSpringStiff
}

// MARK: - Accessibility Support

/// Checks if the user has enabled Reduce Motion in System Preferences > Accessibility
nonisolated func prefersReducedMotion() -> Bool {
    NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
}

/// Returns an animation that respects the user's Reduce Motion preference
/// If Reduce Motion is enabled, returns an instant (zero-duration) animation
extension Animation {
    /// Returns the spring animation, or zero-duration if Reduce Motion is enabled
    static var auroraSpringReduced: Animation {
        prefersReducedMotion() ? .linear(duration: 0) : .auroraSpring
    }
    
    /// Returns the fast animation, or zero-duration if Reduce Motion is enabled
    static var auroraFastReduced: Animation {
        prefersReducedMotion() ? .linear(duration: 0) : .auroraFast
    }
    
    /// Returns the normal animation, or zero-duration if Reduce Motion is enabled
    static var auroraNormalReduced: Animation {
        prefersReducedMotion() ? .linear(duration: 0) : .auroraNormal
    }
    
    /// Returns the slow animation, or zero-duration if Reduce Motion is enabled
    static var auroraSlowReduced: Animation {
        prefersReducedMotion() ? .linear(duration: 0) : .auroraSlow
    }
}

# Graph Report - .  (2026-10-08)

## Corpus Check
- 40 files · ~178,515 words
- Verdict: corpus is large enough that graph structure adds value.

## Summary
- 434 nodes · 647 edges · 40 communities (35 shown, 5 thin omitted)
- Extraction: 86% EXTRACTED · 14% INFERRED · 0% AMBIGUOUS · INFERRED: 93 edges (avg confidence: 0.79)
- Token cost: 0 input · 0 output

## Community Hubs (Navigation)
- [[_COMMUNITY_Settings Configuration|Settings Configuration]]
- [[_COMMUNITY_SwiftUI App Shell|SwiftUI App Shell]]
- [[_COMMUNITY_App State Model|App State Model]]
- [[_COMMUNITY_Configuration Coding|Configuration Coding]]
- [[_COMMUNITY_Shared Data Models|Shared Data Models]]
- [[_COMMUNITY_Google Calendar Service|Google Calendar Service]]
- [[_COMMUNITY_Notifier Errors|Notifier Errors]]
- [[_COMMUNITY_Status Menu Delegate|Status Menu Delegate]]
- [[_COMMUNITY_Leave Check Credentials|Leave Check Credentials]]
- [[_COMMUNITY_Notification Delivery|Notification Delivery]]
- [[_COMMUNITY_LaunchAgent Scheduling|LaunchAgent Scheduling]]
- [[_COMMUNITY_Product Documentation|Product Documentation]]
- [[_COMMUNITY_Kakitangan API Client|Kakitangan API Client]]
- [[_COMMUNITY_Sparkle Updater|Sparkle Updater]]
- [[_COMMUNITY_Asset Metadata|Asset Metadata]]
- [[_COMMUNITY_Icon Asset Variant|Icon Asset Variant]]
- [[_COMMUNITY_Icon Asset Variant|Icon Asset Variant]]
- [[_COMMUNITY_Icon Asset Variant|Icon Asset Variant]]
- [[_COMMUNITY_Icon Asset Variant|Icon Asset Variant]]
- [[_COMMUNITY_Icon Asset Variant|Icon Asset Variant]]
- [[_COMMUNITY_Icon Asset Variant|Icon Asset Variant]]
- [[_COMMUNITY_Icon Asset Variant|Icon Asset Variant]]
- [[_COMMUNITY_Icon Asset Variant|Icon Asset Variant]]
- [[_COMMUNITY_Icon Catalog Metadata|Icon Catalog Metadata]]
- [[_COMMUNITY_Icon Asset Variant|Icon Asset Variant]]
- [[_COMMUNITY_Icon Asset Variant|Icon Asset Variant]]
- [[_COMMUNITY_Icon Asset Variant|Icon Asset Variant]]
- [[_COMMUNITY_Icon Asset Variant|Icon Asset Variant]]
- [[_COMMUNITY_Icon Asset Variant|Icon Asset Variant]]
- [[_COMMUNITY_Icon Asset Variant|Icon Asset Variant]]
- [[_COMMUNITY_Icon Asset Variant|Icon Asset Variant]]
- [[_COMMUNITY_Icon Asset Variant|Icon Asset Variant]]
- [[_COMMUNITY_Icon Asset Variant|Icon Asset Variant]]
- [[_COMMUNITY_Icon Asset Variant|Icon Asset Variant]]
- [[_COMMUNITY_Icon Asset Variant|Icon Asset Variant]]
- [[_COMMUNITY_Icon Asset Variant|Icon Asset Variant]]
- [[_COMMUNITY_Xcode Cloud Manifest|Xcode Cloud Manifest]]

## God Nodes (most connected - your core abstractions)
1. `AppModel` - 50 edges
2. `Kakitangan Leave Notifier` - 28 edges
3. `CodingKeys` - 24 edges
4. `NotifierError` - 22 edges
5. `AppDelegate` - 17 edges
6. `GoogleCalendarService` - 15 edges
7. `CodingKeys` - 12 edges
8. `LaunchAgentService` - 11 edges
9. `NotificationTime` - 11 edges
10. `NotificationService` - 10 edges

## Surprising Connections (you probably didn't know these)
- `Leave Notification Concept` --semantically_similar_to--> `Kakitangan Leave Notifier`  [INFERRED] [semantically similar]
  KakitanganLeaveNotifier/Resources/AppIcon.iconset/icon_32x32@2x.png → README.md
- `Leave Notification Concept` --semantically_similar_to--> `Kakitangan Leave Notifier`  [INFERRED] [semantically similar]
  KakitanganLeaveNotifier/Resources/AppIcon.iconset/icon_128x128.png → README.md
- `Leave Notification Concept` --semantically_similar_to--> `Kakitangan Leave Notifier`  [INFERRED] [semantically similar]
  KakitanganLeaveNotifier/Resources/AppIcon.iconset/icon_256x256@2x.png → README.md
- `Leave Notification Concept` --semantically_similar_to--> `Kakitangan Leave Notifier`  [INFERRED] [semantically similar]
  KakitanganLeaveNotifier/Resources/AppIcon.iconset/icon_32x32.png → README.md
- `Leave Notification Concept` --semantically_similar_to--> `Kakitangan Leave Notifier`  [INFERRED] [semantically similar]
  KakitanganLeaveNotifier/Resources/AppIcon.iconset/icon_512x512.png → README.md

## Hyperedges (group relationships)
- **Google Calendar OAuth and Meeting Sync Flow** — views_contentview_googlecalendarcard, app_appmodel_appmodel_connectgooglecalendar, services_googlecalendarservice_googlecalendarservice_beginauthorization, services_googlecalendarservice_googlecalendarservice_finishauthorization, app_appmodel_appmodel_refreshcalendarevents, services_googlecalendarservice_googlecalendarservice_fetchevents, views_contentview_meetingcalendarcard [EXTRACTED 1.00]
- **Leave Check and Notification Flow** — services_leavecheckservice_leavecheckservice, services_kakitanganapiclient_kakitanganapiclient, services_notificationservice_notificationservice, leave_check_notification_flow [INFERRED 0.85]
- **Release and Sparkle Update Automation** — readme_sparkle_updates, readme_github_release_automation, release_update_automation_flow [INFERRED 0.85]

## Communities (40 total, 5 thin omitted)

### Community 0 - "Settings Configuration"
Cohesion: 0.07
Nodes (29): AppScreen, dashboard, editing, setup, LoginItemStatus, disabled, enabled, notFound (+21 more)

### Community 1 - "SwiftUI App Shell"
Cohesion: 0.07
Nodes (25): App, CheckForUpdatesCommand, KakitanganLeaveNotifierApp, Google Calendar OAuth and Meeting Sync Flow, Keychain Password Storage, View, AccountCard, AppMark (+17 more)

### Community 3 - "Configuration Coding"
Cohesion: 0.05
Nodes (38): CodingKey, CodingKeys, amOrPm, applicant, department, duration, email, endDate (+30 more)

### Community 4 - "Shared Data Models"
Cohesion: 0.09
Nodes (22): Decodable, AuthResponse, DateOnly, KeyedDecodingContainer, LeaveApplicant, LeavePage, LeavePeriod, am (+14 more)

### Community 5 - "Google Calendar Service"
Cohesion: 0.16
Nodes (6): Sendable, Data, GoogleCalendarService, GoogleOAuthLoopbackServer, GoogleOAuthRedirect, String

### Community 6 - "Notifier Errors"
Cohesion: 0.09
Nodes (22): LocalizedError, NotifierError, authenticationFailed, automatedCheckNotConfigured, employeeRequestFailed, googleCalendarAuthenticationFailed, googleCalendarNotConfigured, googleCalendarOAuthDenied (+14 more)

### Community 7 - "Status Menu Delegate"
Cohesion: 0.13
Nodes (6): AppDelegate, applyEffectiveActivationPolicy(), NSApplicationDelegate, NSObject, UNUserNotificationCenterDelegate, ContentView

### Community 8 - "Leave Check Credentials"
Cohesion: 0.17
Nodes (5): Leave Check and Notification Flow, LeaveReport, KeychainStore, BackgroundCheckRunner, LeaveCheckService

### Community 9 - "Notification Delivery"
Cohesion: 0.21
Nodes (6): NotificationPermissionStatus, authorized, denied, notDetermined, unsupported, NotificationService

### Community 12 - "Product Documentation"
Cohesion: 0.29
Nodes (8): App Visibility, First Run Setup Flow, GitHub Release Automation, Kakitangan Leave Notifier, Open at Login, Sign-in Check, Sparkle Software Updates, Release and Sparkle Update Automation

### Community 15 - "Asset Metadata"
Cohesion: 0.4
Nodes (4): images, info, author, version

### Community 16 - "Icon Asset Variant"
Cohesion: 0.67
Nodes (4): App Icon, Approval Mark, Calendar Symbol, Leave Notification Concept

### Community 17 - "Icon Asset Variant"
Cohesion: 0.67
Nodes (4): App Icon, Approval Mark, Calendar Symbol, Leave Notification Concept

### Community 18 - "Icon Asset Variant"
Cohesion: 0.67
Nodes (4): App Icon, Approval Mark, Calendar Symbol, Leave Notification Concept

### Community 19 - "Icon Asset Variant"
Cohesion: 0.67
Nodes (4): App Icon, Approval Mark, Calendar Symbol, Leave Notification Concept

### Community 20 - "Icon Asset Variant"
Cohesion: 0.67
Nodes (4): App Icon, Approval Mark, Calendar Symbol, Leave Notification Concept

### Community 21 - "Icon Asset Variant"
Cohesion: 0.67
Nodes (4): App Icon, Approval Mark, Calendar Symbol, Leave Notification Concept

### Community 22 - "Icon Asset Variant"
Cohesion: 0.67
Nodes (4): App Icon, Approval Mark, Calendar Symbol, Leave Notification Concept

### Community 23 - "Icon Asset Variant"
Cohesion: 0.67
Nodes (4): App Icon, Approval Mark, Calendar Symbol, Leave Notification Concept

### Community 24 - "Icon Catalog Metadata"
Cohesion: 0.5
Nodes (3): info, author, version

### Community 25 - "Icon Asset Variant"
Cohesion: 0.67
Nodes (4): App Icon, Approval Mark, Calendar Symbol, Leave Notification Concept

### Community 26 - "Icon Asset Variant"
Cohesion: 0.67
Nodes (4): App Icon, Approval Mark, Calendar Symbol, Leave Notification Concept

### Community 27 - "Icon Asset Variant"
Cohesion: 0.67
Nodes (4): App Icon, Approval Mark, Calendar Symbol, Leave Notification Concept

### Community 28 - "Icon Asset Variant"
Cohesion: 0.67
Nodes (4): App Icon, Approval Mark, Calendar Symbol, Leave Notification Concept

### Community 29 - "Icon Asset Variant"
Cohesion: 0.67
Nodes (4): App Icon, Approval Mark, Calendar Symbol, Leave Notification Concept

### Community 30 - "Icon Asset Variant"
Cohesion: 0.67
Nodes (4): App Icon, Approval Mark, Calendar Symbol, Leave Notification Concept

### Community 31 - "Icon Asset Variant"
Cohesion: 0.67
Nodes (4): App Icon, Approval Mark, Calendar Symbol, Leave Notification Concept

### Community 32 - "Icon Asset Variant"
Cohesion: 0.67
Nodes (4): App Icon, Approval Mark, Calendar Symbol, Leave Notification Concept

### Community 33 - "Icon Asset Variant"
Cohesion: 0.67
Nodes (4): App Icon, Approval Mark, Calendar Symbol, Leave Notification Concept

### Community 34 - "Icon Asset Variant"
Cohesion: 0.67
Nodes (4): App Icon, Approval Mark, Calendar Symbol, Leave Notification Concept

### Community 35 - "Icon Asset Variant"
Cohesion: 0.67
Nodes (4): App Icon, Approval Mark, Calendar Symbol, Leave Notification Concept

### Community 36 - "Icon Asset Variant"
Cohesion: 0.67
Nodes (4): App Icon, Approval Mark, Calendar Symbol, Leave Notification Concept

## Knowledge Gaps
- **83 isolated node(s):** `setup`, `dashboard`, `editing`, `enabled`, `disabled` (+78 more)
  These have ≤1 connection - possible missing edges or undocumented components.
- **5 thin communities (<3 nodes) omitted from report** — run `graphify query` to explore isolated nodes.

## Suggested Questions
_Questions this graph is uniquely positioned to answer:_

- **Why does `Kakitangan Leave Notifier` connect `Product Documentation` to `SwiftUI App Shell`, `LaunchAgent Scheduling`, `Icon Asset Variant`, `Icon Asset Variant`, `Icon Asset Variant`, `Icon Asset Variant`, `Icon Asset Variant`, `Icon Asset Variant`, `Icon Asset Variant`, `Icon Asset Variant`, `Icon Asset Variant`, `Icon Asset Variant`, `Icon Asset Variant`, `Icon Asset Variant`, `Icon Asset Variant`, `Icon Asset Variant`, `Icon Asset Variant`, `Icon Asset Variant`, `Icon Asset Variant`, `Icon Asset Variant`, `Icon Asset Variant`, `Icon Asset Variant`?**
  _High betweenness centrality (0.346) - this node is a cross-community bridge._
- **Why does `Keychain Password Storage` connect `SwiftUI App Shell` to `Leave Check Credentials`, `Product Documentation`?**
  _High betweenness centrality (0.302) - this node is a cross-community bridge._
- **Why does `AppModel` connect `App State Model` to `Settings Configuration`, `SwiftUI App Shell`, `Configuration Coding`, `Google Calendar Service`, `Status Menu Delegate`, `Sparkle Updater`?**
  _High betweenness centrality (0.238) - this node is a cross-community bridge._
- **Are the 20 inferred relationships involving `Kakitangan Leave Notifier` (e.g. with `Leave Notification Concept` and `Leave Notification Concept`) actually correct?**
  _`Kakitangan Leave Notifier` has 20 INFERRED edges - model-reasoned connections that need verification._
- **What connects `setup`, `dashboard`, `editing` to the rest of the system?**
  _83 weakly-connected nodes found - possible documentation gaps or missing edges._
- **Should `Settings Configuration` be split into smaller, more focused modules?**
  _Cohesion score 0.07 - nodes in this community are weakly interconnected._
- **Should `SwiftUI App Shell` be split into smaller, more focused modules?**
  _Cohesion score 0.07 - nodes in this community are weakly interconnected._
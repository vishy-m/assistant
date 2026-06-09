import Foundation

enum GCalFixtures {
    static let calendarList = """
    {
      "items": [
        { "id": "primary",       "summary": "My Calendar", "primary": true,  "accessRole": "owner" },
        { "id": "school@group",  "summary": "School",      "accessRole": "reader" }
      ]
    }
    """
    static let eventsList = """
    {
      "items": [
        { "id": "ev1",
          "summary": "OS Lecture",
          "start": { "dateTime": "2026-05-14T10:00:00-04:00" },
          "end":   { "dateTime": "2026-05-14T11:30:00-04:00" },
          "location": "ENS 207" }
      ],
      "nextSyncToken": "TOK_NEXT"
    }
    """
    static let createdEvent = """
    {
      "id": "ev_created_1",
      "summary": "Study OS",
      "start": { "dateTime": "2026-05-14T16:00:00-04:00" },
      "end":   { "dateTime": "2026-05-14T18:00:00-04:00" }
    }
    """
    static let recurringInstancesList = """
    {
      "items": [
        { "id": "master1_20260514T140000Z",
          "summary": "Weekly Standup",
          "recurringEventId": "master1",
          "start": { "dateTime": "2026-05-14T10:00:00-04:00" },
          "end":   { "dateTime": "2026-05-14T10:15:00-04:00" } }
      ],
      "nextSyncToken": "TOK_REC"
    }
    """
}

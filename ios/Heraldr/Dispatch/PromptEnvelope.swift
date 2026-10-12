import Foundation

enum PromptEnvelope {
    static let jobIdPlaceholder = "{{job_id}}"
    private static let answerCommand = "/bin/sh \"$HOME/.local/state/heraldr/dispatch.sh\" answer \(jobIdPlaceholder)"

    static func wrap(_ text: String, attachments: [String] = [], for workspace: Workspace) -> String {
        let request = request(text, attachments: attachments)
        return workspace.isHome ? home(request) : standard(request)
    }

    static func forTab(_ text: String, attachments: [String] = []) -> String {
        """
        Request sent from the iPhone (may come from voice dictation: \
        watch for transcription errors).

        \(request(text, attachments: attachments))
        """
    }

    private static func request(_ text: String, attachments: [String]) -> String {
        let text = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !attachments.isEmpty else { return text }
        let paths = attachments.map { "- \($0)" }.joined(separator: "\n")
        return "\(text)\n\nAttached screenshots, read them with Read:\n\(paths)"
    }

    private static func standard(_ request: String) -> String {
        """
        Request sent from the iPhone (may come from voice dictation: \
        watch for transcription errors).

        \(request)

        Instructions:
        - explore the code to understand the request, change nothing here
        - if the request is ambiguous, ask your questions with AskUserQuestion
        - if it is a simple question with no work to do: answer without \
        /start using `\(answerCommand)`, with on standard input a \
        one-sentence summary, a blank line, then the full answer in markdown
        - otherwise, you must finish by dispatching the work with /start
        """
    }

    private static func home(_ request: String) -> String {
        """
        Request sent from the iPhone to Home, the app's default target \
        (may come from voice dictation: watch for transcription errors).

        \(request)

        Instructions:
        - change nothing here
        - if it is a simple question with no work to do: answer it \
        yourself, without relay or /start, exploring whatever you need \
        (including the target project), then hand in your answer using \
        `\(answerCommand)`, with on standard input a one-sentence summary, \
        a blank line, then the full answer in markdown
        - otherwise, identify the target project among the open herdr \
        workspaces: labels with `herdr workspace list`, folders with \
        `herdr pane list --workspace <workspace_id>` (cwd)
        - if several projects could match, ask with AskUserQuestion before \
        any relay
        - if a project is targeted, relay the request to it then stop, \
        without /start: `/bin/sh "$HOME/.local/state/heraldr/dispatch.sh" \
        relay <workspace_id>` with on standard input the original request, \
        fixed for obvious transcription errors, completed with the answers \
        to your questions and followed by the paths of the attached \
        screenshots if any
        - if no open project is concerned: explore whatever you need to \
        understand the request, ask your questions with AskUserQuestion if \
        it is ambiguous, and you must finish by dispatching the work with \
        /start
        """
    }
}

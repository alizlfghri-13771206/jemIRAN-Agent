# Jemiran Agent

[فارسی](README.md) · **English**

An open-source coding agent for Windows that works with your own API keys.

The idea is pretty simple: you choose the model and provider, your key stays on
your machine, and requests go straight from your computer to that provider. No
Jemiran relay server and no extra Jemiran account in the middle.

## So, what can it actually do?

Jemiran is more than a chat box. Give it a task and it can make a plan, use
tools, inspect the results, and verify its work before it wraps up.

- Read, create, and edit files.
- Run commands and work with `git`.
- Inspect web pages.
- Create PDF and Word documents.
- Install a missing tool after getting your permission.
- Summarize context during long tasks so it doesn't lose the thread.
- Keep a local activity log of the important things it does.

## Which models can I use?

Anything that supports one of these two API formats:

| Format | A few examples |
|---|---|
| OpenAI-compatible (`/chat/completions`) | OpenAI, DeepSeek, OpenRouter, Google Gemini, Ollama, and vLLM |
| Anthropic (`/messages`) | Anthropic |

Custom base URLs work too, so you can point Jemiran at a local Ollama or vLLM
server. You can also add more than one provider. If one of them is unavailable,
Jemiran can move on to the next one in your list.

## Getting started

The open-source version currently targets Windows. Install Flutter, open the
project directory, and run:

```bash
flutter pub get
flutter run -d windows
```

Once the app opens, head to **Settings → Add API keys**, choose a provider and
model ID, and enter your API key. That's it.

## Where does my API key go?

Only to the provider you picked.

Jemiran protects the saved key with Windows DPAPI, so it stays encrypted on
your machine. The raw key is not written to the regular config file, exported
settings, or Jemiran's activity logs. Automated tests guard these boundaries;
for example,
[`open_source_boundary_test.dart`](test/desktop/open_source_boundary_test.dart)
checks the repository for private endpoints, credentials, and unknown
infrastructure.

## A quick word before you enable unattended mode

Jemiran can write files and run commands on your computer. That's the useful
part, but it's also something you should treat with care.

- The default **Manual** mode asks before actions that change things. If you're
  unsure, stick with this mode.
- **Unattended** mode can perform some file operations without asking, but
  command execution still needs separate approval.
- File access is limited to the resources you add to each Work.
- Content from websites, files, and command output is treated as data, not as a
  trusted instruction. Dedicated prompt-injection tests cover this boundary.

> Jemiran currently supports Windows only. Secure key storage depends on DPAPI,
> and its local tools rely on Windows features. We'd rather be honest about that
> than claim half-working Linux or macOS support.

## Want to contribute?

You're very welcome. Before opening a pull request, run:

```bash
flutter analyze
flutter test
```

Take a look at [CONTRIBUTING.md](CONTRIBUTING.md) for the contribution guide. If
you find a security issue, please follow [SECURITY.md](SECURITY.md) instead of
opening a public issue.

## License

The code is available under the [MIT License](LICENSE). Third-party notices live
in [THIRD_PARTY_NOTICES.md](THIRD_PARTY_NOTICES.md), and the rules around the
Jemiran name and logo are explained in [TRADEMARKS.md](TRADEMARKS.md).

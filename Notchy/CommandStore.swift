import AppKit
import Foundation
import CryptoKit

struct StoredCommand: Codable {
    var text: String
    var count: Int
    var lastUsed: Date
}

struct CommandFile: Codable {
    var commands: [StoredCommand]
}

class CommandStore {
    static let shared = CommandStore()

    private static let maxCommandsPerDirectory = 500
    private static let maxCachedDirectories = 32

    private let baseDir: URL = {
        let home = FileManager.default.homeDirectoryForCurrentUser
        return home.appendingPathComponent(".notchly/commands")
    }()

    private let queue = DispatchQueue(label: "com.notchly.CommandStore")
    private var cache: [String: [StoredCommand]] = [:]
    private var cacheAccessOrder: [String] = [] // LRU: most-recently used at end
    private var historyImported = false
    private var terminateObserver: NSObjectProtocol?
    private var resignActiveObserver: NSObjectProtocol?

    private init() {
        try? FileManager.default.createDirectory(
            at: baseDir,
            withIntermediateDirectories: true,
            attributes: [.posixPermissions: 0o700]
        )
        // Force-tighten perms in case directory already existed.
        try? FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: baseDir.path)

        // Belt-and-braces: even though every recordCommand persists
        // synchronously on its serial queue (so commands survive a normal
        // quit), make sure any in-flight async writes complete on app exit.
        // Block-based observers don't require NSObject inheritance — the
        // selector-based form silently failed at runtime when this class
        // was a plain Swift class.
        let nc = NotificationCenter.default
        terminateObserver = nc.addObserver(
            forName: NSApplication.willTerminateNotification,
            object: nil, queue: nil
        ) { [weak self] _ in self?.flushSync() }
        resignActiveObserver = nc.addObserver(
            forName: NSApplication.willResignActiveNotification,
            object: nil, queue: nil
        ) { [weak self] _ in self?.flushSync() }
    }

    deinit {
        if let token = terminateObserver { NotificationCenter.default.removeObserver(token) }
        if let token = resignActiveObserver { NotificationCenter.default.removeObserver(token) }
    }

    /// Drain any in-flight async work so all queued writes finish before we
    /// return. Safe to call from any thread.
    func flushSync() {
        queue.sync { /* serial fence */ }
    }

    // MARK: - Public API

    func commands(for directory: String) -> [StoredCommand] {
        queue.sync { _commands(for: directory) }
    }

    func recordCommand(_ command: String, in directory: String) {
        queue.async { [weak self] in
            guard let self else { return }
            var cmds = self._commands(for: directory)
            if let idx = cmds.firstIndex(where: { $0.text == command }) {
                cmds[idx].count += 1
                cmds[idx].lastUsed = Date()
            } else {
                cmds.append(StoredCommand(text: command, count: 1, lastUsed: Date()))
            }
            // Cap at maxCommandsPerDirectory by trimming the oldest least-used
            // entries first (lowest count, then oldest lastUsed).
            if cmds.count > Self.maxCommandsPerDirectory {
                cmds.sort { lhs, rhs in
                    if lhs.count != rhs.count { return lhs.count > rhs.count }
                    return lhs.lastUsed > rhs.lastUsed
                }
                cmds = Array(cmds.prefix(Self.maxCommandsPerDirectory))
            }
            self.updateCache(directory: directory, commands: cmds)
            // Persist immediately on the serial queue. The previous version
            // debounced writes by 2s and relied on app-lifecycle notifications
            // to flush — those notifications never fired because the
            // selector-based observer required NSObject inheritance, so a
            // burst of commands followed by a quit lost all of them.
            self.saveCommands(cmds, for: directory)
        }
    }

    func deleteCommand(_ command: String, in directory: String) {
        queue.async { [weak self] in
            guard let self else { return }
            var cmds = self._commands(for: directory)
            cmds.removeAll { $0.text == command }
            self.updateCache(directory: directory, commands: cmds)
            self.saveCommands(cmds, for: directory)
        }
    }

    func importHistoryIfNeeded(for directory: String) {
        queue.async { [weak self] in
            guard let self else { return }
            guard !self.historyImported else { return }
            self.historyImported = true

            // Read zsh history off the serial queue (it's slow I/O).
            DispatchQueue.global(qos: .utility).async { [weak self] in
                guard let self else { return }
                let historyCommands = self.readZshHistory()

                // Merge back on the serial queue against a FRESH snapshot of cmds,
                // so commands recorded via recordCommand() while we were reading
                // zsh history are preserved (they hit the serial queue first).
                self.queue.async { [weak self] in
                    guard let self else { return }
                    var cmds = self._commands(for: directory)
                    var seen = Set(cmds.map(\.text))

                    if cmds.isEmpty {
                        for cmd in Self.defaultCommands where !seen.contains(cmd) {
                            cmds.append(StoredCommand(text: cmd, count: 1, lastUsed: Date.distantPast))
                            seen.insert(cmd)
                        }
                    }

                    for cmd in historyCommands where !seen.contains(cmd) {
                        cmds.append(StoredCommand(text: cmd, count: 1, lastUsed: Date.distantPast))
                        seen.insert(cmd)
                    }

                    self.updateCache(directory: directory, commands: cmds)
                    self.saveCommands(cmds, for: directory)
                }
            }
        }
    }

    // MARK: - Private (call only from within queue)

    private func _commands(for directory: String) -> [StoredCommand] {
        if let cached = cache[directory] {
            touchCache(directory)
            return cached
        }
        let loaded = loadCommands(for: directory)
        updateCache(directory: directory, commands: loaded)
        return loaded
    }

    private func updateCache(directory: String, commands: [StoredCommand]) {
        cache[directory] = commands
        touchCache(directory)
        if cacheAccessOrder.count > Self.maxCachedDirectories,
           let evicting = cacheAccessOrder.first {
            cacheAccessOrder.removeFirst()
            cache.removeValue(forKey: evicting)
        }
    }

    private func touchCache(_ directory: String) {
        if let idx = cacheAccessOrder.firstIndex(of: directory) {
            cacheAccessOrder.remove(at: idx)
        }
        cacheAccessOrder.append(directory)
    }

    // MARK: - Private

    private func filePath(for directory: String) -> URL {
        let digest = SHA256.hash(data: Data(directory.utf8))
        let hash = digest.map { String(format: "%02x", $0) }.joined()
        return baseDir.appendingPathComponent("\(hash).json")
    }

    private func loadCommands(for directory: String) -> [StoredCommand] {
        let path = filePath(for: directory)
        guard let data = try? Data(contentsOf: path),
              let file = try? JSONDecoder().decode(CommandFile.self, from: data) else {
            return []
        }
        return file.commands
    }

    private func saveCommands(_ commands: [StoredCommand], for directory: String) {
        let path = filePath(for: directory)
        let file = CommandFile(commands: commands)
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        guard let data = try? encoder.encode(file) else { return }
        do {
            try data.write(to: path, options: .atomic)
            try? FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: path.path)
        } catch {
            // Disk full / perm denied — ignore so we don't crash a UI flow.
        }
    }

    // MARK: - Default Commands

    private static let defaultCommands: [String] = [
        // Git
        "git status",
        "git add .",
        "git add -A",
        "git commit -m \"\"",
        "git commit --amend",
        "git push",
        "git push origin main",
        "git push origin master",
        "git push --force-with-lease",
        "git pull",
        "git pull --rebase",
        "git fetch",
        "git fetch --all",
        "git checkout -b ",
        "git checkout main",
        "git checkout master",
        "git checkout develop",
        "git branch",
        "git branch -a",
        "git branch -d ",
        "git merge ",
        "git rebase main",
        "git rebase -i HEAD~",
        "git log --oneline",
        "git log --oneline -20",
        "git log --graph --oneline --all",
        "git diff",
        "git diff --staged",
        "git diff --cached",
        "git stash",
        "git stash pop",
        "git stash list",
        "git stash drop",
        "git reset HEAD~1",
        "git reset --soft HEAD~1",
        "git reset --hard HEAD~1",
        "git cherry-pick ",
        "git tag ",
        "git tag -a ",
        "git remote -v",
        "git clean -fd",
        "git bisect start",
        "git reflog",
        "git blame ",
        "git show ",
        "git rev-parse HEAD",

        // npm
        "npm install",
        "npm install --save-dev ",
        "npm run dev",
        "npm run build",
        "npm run start",
        "npm run test",
        "npm run lint",
        "npm run lint:fix",
        "npm run format",
        "npm run preview",
        "npm run serve",
        "npm run watch",
        "npm run clean",
        "npm run deploy",
        "npm run storybook",
        "npm run e2e",
        "npm run typecheck",
        "npm run generate",
        "npm run db:migrate",
        "npm run db:seed",
        "npm run db:push",
        "npm run db:studio",
        "npm run prisma:generate",
        "npm ci",
        "npm outdated",
        "npm audit",
        "npm audit fix",
        "npm update",
        "npm cache clean --force",
        "npm list --depth=0",
        "npm init -y",
        "npm run coverage",

        // npx
        "npx create-react-app ",
        "npx create-next-app@latest ",
        "npx prisma migrate dev",
        "npx prisma db push",
        "npx prisma studio",
        "npx prisma generate",
        "npx tsc --noEmit",
        "npx eslint . --fix",
        "npx prettier --write .",
        "npx jest --watch",
        "npx vitest",
        "npx playwright test",
        "npx cypress open",
        "npx tailwindcss init",
        "npx expo start",
        "npx expo run:ios",
        "npx expo run:android",
        "npx react-native run-ios",
        "npx react-native run-android",

        // yarn
        "yarn install",
        "yarn dev",
        "yarn build",
        "yarn start",
        "yarn test",
        "yarn lint",
        "yarn lint:fix",
        "yarn format",
        "yarn add ",
        "yarn add -D ",
        "yarn remove ",
        "yarn upgrade",
        "yarn ios",
        "yarn android",
        "yarn storybook",
        "yarn typecheck",
        "yarn clean",
        "yarn cache clean",

        // pnpm
        "pnpm install",
        "pnpm dev",
        "pnpm build",
        "pnpm start",
        "pnpm test",
        "pnpm lint",
        "pnpm add ",
        "pnpm add -D ",
        "pnpm remove ",
        "pnpm run ",
        "pnpm dlx ",
        "pnpm store prune",

        // bun
        "bun install",
        "bun dev",
        "bun run dev",
        "bun run build",
        "bun run start",
        "bun run test",
        "bun add ",
        "bun add -d ",
        "bun remove ",
        "bun upgrade",
        "bun init",
        "bun create ",

        // Python
        "python manage.py runserver",
        "python manage.py migrate",
        "python manage.py makemigrations",
        "python manage.py createsuperuser",
        "python manage.py shell",
        "python manage.py test",
        "python manage.py collectstatic",
        "python -m pytest",
        "python -m pytest -v",
        "python -m pytest --cov",
        "python -m venv venv",
        "python -m pip install -r requirements.txt",
        "python -m pip freeze > requirements.txt",
        "python -m http.server",
        "python3 -m venv venv",
        "pip install -r requirements.txt",
        "pip install ",
        "pip freeze > requirements.txt",
        "pip list",
        "pip install --upgrade pip",
        "source venv/bin/activate",
        "deactivate",
        "uvicorn main:app --reload",
        "gunicorn app:app",
        "flask run",
        "flask db upgrade",
        "flask db migrate",
        "poetry install",
        "poetry add ",
        "poetry run ",
        "poetry shell",
        "poetry update",
        "poetry lock",
        "pytest",
        "pytest -v",
        "pytest -x",
        "pytest --cov",
        "pytest -k ",
        "black .",
        "isort .",
        "flake8 .",
        "mypy .",
        "ruff check .",
        "ruff check --fix .",

        // Ruby / Rails
        "bundle install",
        "bundle exec ",
        "bundle update",
        "rails server",
        "rails console",
        "rails db:migrate",
        "rails db:seed",
        "rails db:create",
        "rails db:drop",
        "rails db:reset",
        "rails generate ",
        "rails routes",
        "rails test",
        "rake ",
        "gem install ",
        "rspec",
        "rubocop",
        "rubocop -A",

        // Go
        "go build",
        "go build ./...",
        "go run .",
        "go run main.go",
        "go test ./...",
        "go test -v ./...",
        "go test -race ./...",
        "go test -cover ./...",
        "go test -bench .",
        "go mod init ",
        "go mod tidy",
        "go mod download",
        "go mod vendor",
        "go get ",
        "go fmt ./...",
        "go vet ./...",
        "go generate ./...",
        "go install ",
        "golangci-lint run",
        "air",

        // Rust
        "cargo build",
        "cargo build --release",
        "cargo run",
        "cargo run --release",
        "cargo test",
        "cargo test -- --nocapture",
        "cargo bench",
        "cargo check",
        "cargo clippy",
        "cargo clippy -- -W clippy::all",
        "cargo fmt",
        "cargo doc --open",
        "cargo add ",
        "cargo remove ",
        "cargo update",
        "cargo clean",
        "cargo init ",
        "cargo new ",
        "cargo publish",
        "rustup update",

        // Java / Kotlin / JVM
        "mvn clean install",
        "mvn clean package",
        "mvn test",
        "mvn spring-boot:run",
        "mvn compile",
        "mvn dependency:tree",
        "gradle build",
        "gradle run",
        "gradle test",
        "gradle clean",
        "gradle bootRun",
        "./gradlew build",
        "./gradlew run",
        "./gradlew test",
        "./gradlew clean",
        "./gradlew bootRun",

        // PHP / Laravel
        "php artisan serve",
        "php artisan migrate",
        "php artisan migrate:fresh --seed",
        "php artisan make:model ",
        "php artisan make:controller ",
        "php artisan make:migration ",
        "php artisan tinker",
        "php artisan cache:clear",
        "php artisan config:clear",
        "php artisan route:list",
        "php artisan queue:work",
        "php artisan test",
        "php artisan db:seed",
        "php artisan key:generate",
        "php artisan storage:link",
        "php artisan schedule:run",
        "php artisan optimize",
        "composer install",
        "composer update",
        "composer require ",
        "composer dump-autoload",
        "composer test",
        "phpunit",
        "php -S localhost:8000",

        // Docker
        "docker build -t ",
        "docker build .",
        "docker run ",
        "docker run -it ",
        "docker run -d -p ",
        "docker ps",
        "docker ps -a",
        "docker images",
        "docker stop ",
        "docker rm ",
        "docker rmi ",
        "docker logs ",
        "docker logs -f ",
        "docker exec -it ",
        "docker pull ",
        "docker push ",
        "docker system prune",
        "docker system prune -a",
        "docker volume ls",
        "docker volume prune",
        "docker network ls",
        "docker inspect ",
        "docker-compose up",
        "docker-compose up -d",
        "docker-compose up --build",
        "docker-compose down",
        "docker-compose down -v",
        "docker-compose logs -f",
        "docker-compose ps",
        "docker-compose exec ",
        "docker-compose build",
        "docker-compose restart",
        "docker compose up",
        "docker compose up -d",
        "docker compose up --build",
        "docker compose down",
        "docker compose down -v",
        "docker compose logs -f",
        "docker compose ps",
        "docker compose exec ",
        "docker compose build",

        // Kubernetes
        "kubectl get pods",
        "kubectl get pods -A",
        "kubectl get services",
        "kubectl get deployments",
        "kubectl get nodes",
        "kubectl get namespaces",
        "kubectl get all",
        "kubectl get ingress",
        "kubectl describe pod ",
        "kubectl describe service ",
        "kubectl logs ",
        "kubectl logs -f ",
        "kubectl exec -it ",
        "kubectl apply -f ",
        "kubectl delete -f ",
        "kubectl port-forward ",
        "kubectl rollout restart ",
        "kubectl rollout status ",
        "kubectl scale ",
        "kubectl top pods",
        "kubectl top nodes",
        "kubectl config get-contexts",
        "kubectl config use-context ",

        // Terraform
        "terraform init",
        "terraform plan",
        "terraform apply",
        "terraform apply -auto-approve",
        "terraform destroy",
        "terraform fmt",
        "terraform validate",
        "terraform output",
        "terraform state list",
        "terraform import ",
        "terraform workspace list",
        "terraform workspace select ",

        // AWS CLI
        "aws s3 ls",
        "aws s3 cp ",
        "aws s3 sync ",
        "aws ec2 describe-instances",
        "aws ecs list-services",
        "aws lambda list-functions",
        "aws cloudformation deploy ",
        "aws sts get-caller-identity",
        "aws configure",
        "aws logs tail ",
        "aws ssm start-session --target ",

        // macOS / Xcode / Swift
        "xcodebuild -project ",
        "xcodebuild -workspace ",
        "xcodebuild clean build",
        "xcodebuild -scheme ",
        "xcodebuild test",
        "swift build",
        "swift run",
        "swift test",
        "swift package init",
        "swift package update",
        "swift package resolve",
        "swift format ",
        "swiftlint",
        "swiftlint --fix",
        "pod install",
        "pod update",
        "pod repo update",
        "xcode-select --install",
        "xcrun simctl list",
        "xcrun simctl boot ",
        "open -a Simulator",
        "open *.xcworkspace",
        "open *.xcodeproj",

        // System / Shell
        "ls -la",
        "ls -lah",
        "ls -R",
        "cat ",
        "less ",
        "head -n 20 ",
        "tail -f ",
        "tail -n 100 ",
        "grep -r \"\" .",
        "grep -rn \"\" .",
        "grep -ri \"\" .",
        "find . -name \"\"",
        "find . -type f -name \"\"",
        "find . -type d -name \"\"",
        "wc -l ",
        "du -sh *",
        "du -sh .",
        "df -h",
        "top",
        "htop",
        "ps aux",
        "ps aux | grep ",
        "kill -9 ",
        "killall ",
        "lsof -i :",
        "lsof -i :3000",
        "lsof -i :8080",
        "netstat -an | grep LISTEN",
        "curl -X GET ",
        "curl -X POST ",
        "curl -s ",
        "curl -I ",
        "wget ",
        "ssh ",
        "scp ",
        "rsync -avz ",
        "chmod +x ",
        "chmod 755 ",
        "chmod 644 ",
        "chown ",
        "ln -s ",
        "tar -czf ",
        "tar -xzf ",
        "zip -r ",
        "unzip ",
        "which ",
        "whereis ",
        "whoami",
        "hostname",
        "ifconfig",
        "ping ",
        "traceroute ",
        "dig ",
        "nslookup ",
        "env | grep ",
        "export ",
        "echo $PATH",
        "echo $HOME",
        "source ~/.zshrc",
        "source ~/.bashrc",
        "history | grep ",
        "xargs ",
        "sed -i '' ",
        "awk '{print $1}' ",
        "sort ",
        "sort -u ",
        "uniq ",
        "tee ",
        "watch ",
        "time ",
        "open .",
        "open -a \"Visual Studio Code\" .",
        "code .",
        "subl .",
        "vim ",
        "nano ",

        // Homebrew
        "brew install ",
        "brew uninstall ",
        "brew update",
        "brew upgrade",
        "brew list",
        "brew search ",
        "brew info ",
        "brew services list",
        "brew services start ",
        "brew services stop ",
        "brew services restart ",
        "brew doctor",
        "brew cleanup",
        "brew tap ",
        "brew cask install ",

        // Database
        "psql ",
        "psql -U postgres",
        "pg_dump ",
        "pg_restore ",
        "mysql -u root -p",
        "mysqldump ",
        "mongosh",
        "mongo",
        "redis-cli",
        "redis-cli ping",
        "redis-server",
        "sqlite3 ",

        // Elixir / Phoenix
        "mix phx.server",
        "mix deps.get",
        "mix ecto.migrate",
        "mix ecto.create",
        "mix ecto.reset",
        "mix test",
        "mix format",
        "mix compile",
        "iex -S mix",
        "iex -S mix phx.server",

        // .NET / C#
        "dotnet run",
        "dotnet build",
        "dotnet test",
        "dotnet watch run",
        "dotnet ef migrations add ",
        "dotnet ef database update",
        "dotnet restore",
        "dotnet publish",
        "dotnet new ",
        "dotnet add package ",

        // Deno
        "deno run ",
        "deno task dev",
        "deno task build",
        "deno task start",
        "deno test",
        "deno fmt",
        "deno lint",
        "deno compile ",

        // Claude Code — CLI
        "claude",
        "claude --help",
        "claude --version",
        "claude --resume",
        "claude --continue",
        "claude --verbose",
        "claude --model opus",
        "claude --model sonnet",
        "claude --model claude-opus-4-6",
        "claude --model claude-sonnet-4-6",
        "claude --model claude-haiku-4-5-20251001",
        "claude --effort max",
        "claude --effort high",
        "claude --effort medium",
        "claude --effort low",
        "claude --permission-mode auto",
        "claude --permission-mode plan",
        "claude --permission-mode default",
        "claude --permission-mode bypassPermissions",
        "claude --permission-mode acceptEdits",
        "claude --dangerously-skip-permissions",
        "claude --allow-dangerously-skip-permissions",
        "claude --allowed-tools ",
        "claude --disallowed-tools ",
        "claude --tools ",
        "claude --chrome",
        "claude --no-chrome",
        "claude --bare",
        "claude --debug",
        "claude --debug-file ",
        "claude --worktree",
        "claude --ide",
        "claude --add-dir ",
        "claude --system-prompt \"\"",
        "claude --append-system-prompt \"\"",
        "claude --mcp-config ",
        "claude --name \"\"",
        "claude --from-pr ",
        "claude --fork-session --resume",
        "claude --max-budget-usd ",
        // Claude Code — print mode
        "claude -p \"\"",
        "claude -p \"\" --output-format json",
        "claude -p \"\" --output-format text",
        "claude -p \"\" --output-format stream-json",
        "claude -p \"\" --model opus",
        "claude -p \"\" --model sonnet",
        "claude -p \"\" --verbose",
        "claude -p \"\" --json-schema ",
        "claude -p \"\" --max-budget-usd ",
        "claude -p \"\" --fallback-model sonnet",
        "cat file | claude -p \"\"",
        "git diff | claude -p \"review this diff\"",
        "claude -p \"explain this codebase\"",
        "claude -p \"find bugs in this code\"",
        "claude -p \"write tests for this file\"",
        "claude -p \"refactor this function\"",
        // Claude Code — subcommands
        "claude update",
        "claude doctor",
        "claude auth",
        "claude setup-token",
        "claude install",
        "claude agents",
        "claude mcp list",
        "claude mcp add ",
        "claude mcp remove ",
        "claude mcp serve",
        "claude plugin list",
        "claude auto-mode",
        "claude auto-mode config",
        "claude auto-mode defaults",
        "claude auto-mode critique",

        // Misc dev tools
        "make",
        "make build",
        "make test",
        "make clean",
        "make install",
        "make run",
        "cmake .",
        "cmake --build .",
        "nginx -t",
        "nginx -s reload",
        "systemctl status ",
        "systemctl restart ",
        "journalctl -u ",
        "journalctl -f",
        "pm2 list",
        "pm2 start ",
        "pm2 restart all",
        "pm2 logs",
        "pm2 monit",
        "vercel",
        "vercel --prod",
        "netlify deploy",
        "netlify deploy --prod",
        "fly deploy",
        "fly logs",
        "heroku logs --tail",
        "heroku run ",
        "gh pr create",
        "gh pr list",
        "gh pr checkout ",
        "gh pr view",
        "gh issue list",
        "gh issue create",
        "gh repo clone ",
        "gh run list",
        "gh run watch",
    ]

    private func readZshHistory() -> [String] {
        let home = FileManager.default.homeDirectoryForCurrentUser
        let historyPath = home.appendingPathComponent(".zsh_history")
        guard let content = try? String(contentsOf: historyPath, encoding: .utf8) else { return [] }

        var commands: [String] = []
        let seen = NSMutableSet()

        for line in content.components(separatedBy: "\n").reversed() {
            guard !line.isEmpty else { continue }
            // zsh history format: ": timestamp:0;command" or just "command"
            let cmd: String
            if line.hasPrefix(": "), let semicolonIdx = line.firstIndex(of: ";") {
                cmd = String(line[line.index(after: semicolonIdx)...])
            } else {
                cmd = line
            }

            let trimmed = cmd.trimmingCharacters(in: .whitespaces)
            guard !trimmed.isEmpty, trimmed.count >= 2 else { continue }
            // Skip single-word trivial commands
            guard !["ls", "cd", "pwd", "clear", "exit"].contains(trimmed) else { continue }

            if !seen.contains(trimmed) {
                seen.add(trimmed)
                commands.append(trimmed)
            }

            if commands.count >= 500 { break }
        }

        return commands
    }
}

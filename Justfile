set shell := ["fish", "-c"]

# Reusable paths
derived_data := "./build"
agent_app := derived_data + "/Build/Products/Debug/SecretAgent.app"
agent_bin := agent_app + "/Contents/MacOS/SecretAgent"
agent_socket := "$HOME/Library/Containers/com.razmser.Secretive.SecretAgent/Data/socket-debug.ssh"
agent_log := "/tmp/secretive-agent.log"

# Build the debug SecretAgent with a pinned DerivedData location.
build:
	xcodebuild -project Sources/Secretive.xcodeproj -scheme SecretAgent -configuration Debug -derivedDataPath {{derived_data}} build

# Remove derived data and logs for a fresh build.
clean:
	xcodebuild -project Sources/Secretive.xcodeproj -scheme SecretAgent -configuration Debug -derivedDataPath {{derived_data}} clean
	rm -rf {{derived_data}} "{{agent_log}}"

# Build and launch the locally built Secretive GUI (Debug).
open:
	xcodebuild -project Sources/Secretive.xcodeproj -scheme Secretive -configuration Debug -derivedDataPath {{derived_data}} build
	set app "{{derived_data}}/Build/Products/Debug/Secretive.app"; if not test -d "$app"; echo "Missing $app; build may have failed."; exit 1; end; open "$app"

# Stop any running SecretAgent processes to free the debug socket.
kill:
	pkill -f SecretAgent || true

# Kill, rebuild, and launch the agent in the foreground.
run: kill build
	mkdir -p (dirname "{{agent_socket}}")
	if not test -x "{{agent_bin}}"; echo "SecretAgent binary missing at {{agent_bin}}; build may have failed."; exit 1; end
	echo "export SSH_AUTH_SOCK={{agent_socket}}"
	echo "Starting SecretAgent in foreground..."
	env SSH_AUTH_SOCK="{{agent_socket}}" "{{agent_bin}}"

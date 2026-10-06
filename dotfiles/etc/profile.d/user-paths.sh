# Add per-user directories to PATH
user_paths=(
    "$HOME/.cargo/bin"
    "$HOME/.dotnet/tools"
)

for dir in "${user_paths[@]}"; do
    case ":$PATH:" in
        *":$dir:"*) ;;
        *) PATH="$PATH:$dir" ;;
    esac
done
export PATH
unset dir user_paths

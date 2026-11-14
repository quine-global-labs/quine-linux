# quine-app-updates' menu entries ahead of Flatpak's (flatpak.sh, which runs
# first). Same as /usr/lib/systemd/user-environment-generators/61-quine-app-launchers.
case ":${XDG_DATA_DIRS}:" in
  *:/var/lib/quine-linux/app-launchers:*) ;;
  *) XDG_DATA_DIRS="${XDG_STATE_HOME:-$HOME/.local/state}/quine-linux/app-launchers:/var/lib/quine-linux/app-launchers${XDG_DATA_DIRS:+:$XDG_DATA_DIRS}"
     export XDG_DATA_DIRS ;;
esac

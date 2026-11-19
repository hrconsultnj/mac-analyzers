# shellcheck shell=bash
# Folder move for an update. Sourced by upgrade.command after the checkout,
# never run on its own. Bash 3.2. It does not edit config.local.sh.
#
# Suite folders: memory-analyzer, storage-analyzer and network-analyzer become
# memory, storage and network. While the rest of this update is still running
# the old name is a link, so the updater people already have can finish.
# sparehold_remove_old_names then deletes that name. A real folder is deleted
# only when every file in it is already in the new folder and identical, so
# one copy remains and nothing unique is thrown away.
#
# Home folder: a checkout whose physical path is exactly ~/mac-analyzers, and
# only when ~/sparehold does not exist, is moved to ~/sparehold. The old name
# is removed when the update has finished. Any other checkout is not moved.

# 0 when a link at this path would not show up as an uncommitted change.
sparehold_may_link() {
  local path="$1"
  [[ -e .git ]] || return 0
  git check-ignore -q -- "$path"
}

# Rename one old suite directory onto its new name, fold in files the new
# directory does not already have, and leave the old name as a relative link.
sparehold_fold_suite_dir() {
  local old="$1" new="$2" path rel dest moved
  [[ -L "$old" ]] && return 0
  if [[ ! -d "$old" && ! -d "$new" ]]; then
    return 0
  fi
  if [[ -d "$old" && ! -e "$new" && ! -L "$new" ]]; then
    mv -- "$old" "$new"
    echo "→ renamed ${old}/ to ${new}/"
  fi
  if [[ -d "$old" && ! -L "$old" && -d "$new" ]]; then
    moved=0
    while IFS= read -r path; do
      [[ -n "$path" ]] || continue
      rel="${path#"$old"/}"
      [[ -n "$rel" && "$rel" != "$path" ]] || continue
      dest="$new/$rel"
      if [[ -e "$dest" || -L "$dest" ]]; then
        continue
      fi
      mkdir -p -- "$(dirname -- "$dest")"
      mv -- "$path" "$dest"
      moved=1
    done < <(find "$old" -mindepth 1 \( -type f -o -type l \) -print)
    find "$old" -depth -type d -empty -exec rmdir {} \;
    if [[ -d "$old" ]]; then
      echo "→ left ${old}/ in place; it still has files that ${new}/ also has"
    elif [[ "$moved" -eq 1 ]]; then
      echo "→ moved what only ${old}/ had into ${new}/"
    fi
  fi
  if [[ -d "$new" && ! -e "$old" && ! -L "$old" ]]; then
    if sparehold_may_link "$old"; then
      ln -s -- "$new" "$old"
      echo "→ ${old} points at ${new}, so older paths keep working"
    else
      echo "→ left ${old} unlinked so this checkout does not show an uncommitted change"
    fi
  fi
}

# A relative link beside the new file, when the old name is absent.
sparehold_link_old_name() {
  local old="$1" target="$2" dir
  dir="$(dirname -- "$old")"
  [[ -e "$dir/$target" || -L "$dir/$target" ]] || return 0
  [[ -e "$old" || -L "$old" ]] && return 0
  if sparehold_may_link "$old"; then
    ln -s -- "$target" "$old"
    echo "→ ${old} points at ${target}, so the older name keeps working"
  fi
}

# Move this checkout from ~/mac-analyzers to ~/sparehold when that is exactly
# where it is, and leave the old name working. Sets MA_UPGRADE_ROOT and the
# working directory to the new path when it moves.
sparehold_migrate_home() {
  local physical inode dest_inode home_checkout
  physical="$(pwd -P)" || return 1
  # A link is already migrated. Compare physical paths: /var and /private/var
  # are the same folder on macOS, and only the real directory at this name moves.
  [[ -d "$HOME/mac-analyzers" && ! -L "$HOME/mac-analyzers" ]] || return 0
  home_checkout="$(cd "$HOME/mac-analyzers" && pwd -P)" || return 1
  [[ "$physical" == "$home_checkout" ]] || return 0
  if [[ -e "$HOME/sparehold" || -L "$HOME/sparehold" ]]; then
    echo "→ left this checkout at ~/mac-analyzers because ~/sparehold already exists"
    return 0
  fi
  echo "→ moving ~/mac-analyzers to ~/sparehold…"
  inode="$(stat -f %i "$physical")" || return 1
  if ! mv -- "$physical" "$HOME/sparehold"; then
    echo "✗ Could not move ~/mac-analyzers to ~/sparehold. Nothing else was changed."
    return 1
  fi
  dest_inode="$(stat -f %i "$HOME/sparehold" 2>/dev/null || true)"
  if [[ -z "$dest_inode" || "$inode" != "$dest_inode" ]]; then
    if [[ -d "$HOME/sparehold/mac-analyzers" ]]; then
      mv -- "$HOME/sparehold/mac-analyzers" "$HOME/mac-analyzers"
    fi
    echo "→ left this checkout at ~/mac-analyzers because ~/sparehold already exists"
    return 0
  fi
  if ! ln -s -- sparehold "$HOME/mac-analyzers"; then
    mv -- "$HOME/sparehold" "$HOME/mac-analyzers"
    echo "✗ Could not leave ~/mac-analyzers as a link, so the folder was put back."
    return 1
  fi
  export MA_UPGRADE_ROOT="$HOME/sparehold"
  cd "$HOME/sparehold" || return 1
  if [[ -e .git ]]; then
    git worktree repair >/dev/null 2>&1 || true
  fi
}

sparehold_migrate_layout() {
  sparehold_fold_suite_dir memory-analyzer memory
  sparehold_fold_suite_dir storage-analyzer storage
  sparehold_fold_suite_dir network-analyzer network
  sparehold_link_old_name extras/swiftbar-plugin/mac-analyzers.5m.sh sparehold.5m.sh
  sparehold_migrate_home
}

# Delete one old name once the new one already has those files. A link to the
# new name is removed. A real folder loses only the files that match, and is
# removed when nothing is left. A file that differs is kept.
sparehold_remove_duplicate_dir() {
  local old="$1" new="$2" path rel dest target
  if [[ -L "$old" ]]; then
    target="$(readlink "$old")"
    if [[ "$target" == "$new" ]]; then
      rm -- "$old"
      echo "→ removed ${old}"
    fi
    return 0
  fi
  [[ -d "$old" && -d "$new" ]] || return 0
  while IFS= read -r path; do
    [[ -n "$path" ]] || continue
    rel="${path#"$old"/}"
    [[ -n "$rel" && "$rel" != "$path" ]] || continue
    dest="$new/$rel"
    if [[ -e "$dest" || -L "$dest" ]] && cmp -s "$path" "$dest"; then
      rm -f -- "$path"
    fi
  done < <(find "$old" -mindepth 1 \( -type f -o -type l \) -print)
  find "$old" -depth -type d -empty -exec rmdir {} \;
  if [[ -d "$old" ]]; then
    echo "→ left ${old}/ because it still has something ${new}/ does not"
  else
    echo "→ removed ${old}"
  fi
}

# The old home name, when it is only a link to ~/sparehold.
sparehold_remove_home_link() {
  local link_real spare_real
  [[ -L "$HOME/mac-analyzers" && -d "$HOME/sparehold" ]] || return 0
  link_real="$(cd "$HOME/mac-analyzers" && pwd -P)" || return 0
  spare_real="$(cd "$HOME/sparehold" && pwd -P)" || return 0
  [[ "$link_real" == "$spare_real" ]] || return 0
  if [[ -e "$HOME/sparehold/.git" ]]; then
    git -C "$HOME/sparehold" worktree repair >/dev/null 2>&1 || true
  fi
  rm -- "$HOME/mac-analyzers"
  echo "→ removed ~/mac-analyzers"
}

# Call from the checkout root, after the update has finished using the old names.
sparehold_remove_old_names() {
  local plugin="extras/swiftbar-plugin/mac-analyzers.5m.sh"
  sparehold_remove_duplicate_dir memory-analyzer memory
  sparehold_remove_duplicate_dir storage-analyzer storage
  sparehold_remove_duplicate_dir network-analyzer network
  if [[ -L "$plugin" && "$(readlink "$plugin")" == "sparehold.5m.sh" ]]; then
    rm -- "$plugin"
    echo "→ removed ${plugin}"
  fi
  sparehold_remove_home_link
}

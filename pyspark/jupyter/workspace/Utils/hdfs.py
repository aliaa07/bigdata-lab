# hdfs_wrapper.py - Run this once to set up
from IPython.core.magic import register_cell_magic
from pyspark.sql import SparkSession
from functools import partial


class HDFS:
    """
    Pure PySpark wrapper around Hadoop FileSystem API.
    Accesses HDFS via spark._jvm - no subprocess, no shell.
    """
    
    def __init__(self, spark: SparkSession):
        self._spark = spark
        self._jvm = spark._jvm
        self._jsc = spark._jsc
        self._conf = spark._jsc.hadoopConfiguration()
        self._fs = self._jvm.org.apache.hadoop.fs.FileSystem.get(self._conf)
        self._Path = self._jvm.org.apache.hadoop.fs.Path
    
    # ═══════════════════════════════════════════
    #  NAVIGATION & LISTING
    # ═══════════════════════════════════════════
    
    def ls(self, path: str, recursive: bool = False, human: bool = False):
        """
        List directory contents.
        
        Usage:
            hdfs.ls("/user/jovyan")
            hdfs.ls("/user/jovyan", recursive=True)
            hdfs.ls("/user/jovyan", human=True)
        """
        p = self._Path(path)
        if not self._fs.exists(p):
            print(f"Path does not exist: {path}")
            return
        
        if recursive:
            status = self._fs.listStatus(p)
            self._print_files_recursive(status, human, indent="")
        else:
            status = self._fs.listStatus(p)
            self._print_list(status, human)
    
    def _print_list(self, status, human=False):
        """Pretty print file listing."""
        print(f"{'PERMISSIONS':<12} {'REPL':<4} {'OWNER':<10} {'GROUP':<10} {'SIZE':>15} {'MODIFIED':<20} {'NAME'}")
        print("-" * 120)
        for s in sorted(status, key=lambda x: x.getPath().getName()):
            stat = s
            p = s.getPath()
            perms = self._octal_to_perms(stat.getPermission().toShort())
            repl = stat.getReplication()
            owner = stat.getOwner()
            group = stat.getGroup()
            size = stat.getLen()
            # Simple time format
            from datetime import datetime
            mod_dt = datetime.fromtimestamp(stat.getModificationTime() / 1000)
            size_str = self._human_size(size) if human else str(size)
            is_dir = "d" if stat.isDirectory() else "-"
            print(f"{is_dir}{perms:<11} {repl:<4} {owner:<10} {group:<10} {size_str:>15} {str(mod_dt):<20} {p.getName()}")
    
    def _print_files_recursive(self, status, human, indent):
        for s in status:
            p = s.getPath()
            size = self._human_size(s.getLen()) if human else str(s.getLen())
            is_dir = "DIR " if s.isDirectory() else "FILE"
            print(f"{indent}{is_dir:<5} {size:>12}  {p}")
            if s.isDirectory():
                try:
                    sub = self._fs.listStatus(p)
                    self._print_files_recursive(sub, human, indent + "  ")
                except:
                    pass
    
    def exists(self, path: str) -> bool:
        """Check if path exists."""
        return self._fs.exists(self._Path(path))
    
    def info(self, path: str):
        """Show file/directory info."""
        p = self._Path(path)
        if not self._fs.exists(p):
            print(f"Path does not exist: {path}")
            return
        
        if self._fs.isFile(p):
            s = self._fs.getFileStatus(p)
            print(f"Path:        {s.getPath()}")
            print(f"Type:        FILE")
            print(f"Size:        {self._human_size(s.getLen())}")
            print(f"Replication: {s.getReplication()}")
            print(f"Block size:  {self._human_size(s.getBlockSize())}")
            print(f"Owner:       {s.getOwner()}")
            print(f"Group:       {s.getGroup()}")
            print(f"Permissions: {self._octal_to_perms(s.getPermission().toShort())}")
            from datetime import datetime
            mod_dt = datetime.fromtimestamp(s.getModificationTime() / 1000)
            acc_dt = datetime.fromtimestamp(s.getAccessTime() / 1000)
            print(f"Modified:    {mod_dt}")
            print(f"Accessed:    {acc_dt}")
        else:
            # Directory info
            contents = self._fs.listStatus(p)
            print(f"Path:        {path}")
            print(f"Type:        DIRECTORY")
            print(f"Contents:    {len(contents)} items")
            total_size = sum(s.getLen() for s in contents if not s.isDirectory())
            print(f"Total Size:  {self._human_size(total_size)}")
    
    # ═══════════════════════════════════════════
    #  READING FILES
    # ═══════════════════════════════════════════
    
    def cat(self, path: str, max_lines: int = None, encoding: str = "utf-8"):
        """
        Display file contents.
        
        Usage:
            hdfs.cat("/user/jovyan/file.csv")
            hdfs.cat("/user/jovyan/file.csv", max_lines=20)
        """
        p = self._Path(path)
        if not self._fs.exists(p):
            print(f"File not found: {path}")
            return
        
        fs_data = self._fs.open(p)
        try:
            if max_lines:
                line_count = 0
                reader = self._jvm.java.io.BufferedReader(
                    self._jvm.java.io.InputStreamReader(fs_data, encoding)
                )
                line = reader.readLine()
                while line is not None and line_count < max_lines:
                    print(line)
                    line_count += 1
                    line = reader.readLine()
            else:
                reader = self._jvm.java.io.BufferedReader(
                    self._jvm.java.io.InputStreamReader(fs_data, encoding)
                )
                line = reader.readLine()
                while line is not None:
                    print(line)
                    line = reader.readLine()
        finally:
            fs_data.close()
    
    def head(self, path: str, n: int = 10, encoding: str = "utf-8"):
        """Display first N lines of a file."""
        self.cat(path, max_lines=n, encoding=encoding)
    
    def tail(self, path: str, n: int = 10, encoding: str = "utf-8"):
        """Display last N lines of a file."""
        p = self._Path(path)
        if not self._fs.exists(p):
            print(f"File not found: {path}")
            return
        
        fs_data = self._fs.open(p)
        try:
            reader = self._jvm.java.io.BufferedReader(
                self._jvm.java.io.InputStreamReader(fs_data, encoding)
            )
            lines = []
            line = reader.readLine()
            while line is not None:
                lines.append(line)
                if len(lines) > n:
                    lines.pop(0)
                line = reader.readLine()
            
            for line in lines:
                print(line)
        finally:
            fs_data.close()
    
    def read(self, path: str, start: int = 0, length: int = None, encoding: str = "utf-8"):
        """
        Read file bytes (for binary files or partial reads).
        
        Usage:
            hdfs.read("/path/to/file")                    # full file
            hdfs.read("/path/to/file", length=1024)       # first 1KB
            hdfs.read("/path/to/file", start=100, length=200)  # bytes 100-300
        """
        p = self._Path(path)
        if not self._fs.exists(p):
            print(f"File not found: {path}")
            return
        
        fs_data = self._fs.open(p)
        try:
            if start > 0:
                fs_data.seek(start)
            
            if length:
                buf = bytearray(length)
                bytes_read = fs_data.read(buf, 0, length)
                return bytes(buf[:bytes_read]) if bytes_read > 0 else b""
            else:
                # Read all
                from io import BytesIO
                output = BytesIO()
                buf_size = 4096
                buf = bytearray(buf_size)
                while True:
                    bytes_read = fs_data.read(buf, 0, buf_size)
                    if bytes_read <= 0:
                        break
                    output.write(buf[:bytes_read])
                return output.getvalue()
        finally:
            fs_data.close()
    
    # ═══════════════════════════════════════════
    #  WRITING & TRANSFERRING
    # ═══════════════════════════════════════════
    
    def put(self, local_path: str, hdfs_path: str, overwrite: bool = True):
        """
        Upload local file to HDFS.
        
        Usage:
            hdfs.put("/local/file.csv", "/user/jovyan/file.csv")
            hdfs.put("/local/file.csv", "/user/jovyan/file.csv", overwrite=False)
        """
        src = self._Path(local_path)
        dst = self._Path(hdfs_path)
        
        if not self._jvm.java.io.File(local_path).exists():
            print(f"Local file not found: {local_path}")
            return
        
        # Ensure parent dir exists
        self._fs.mkdirs(dst.getParent())
        
        # Copy
        self._fs.copyFromLocalFile(False, overwrite, src, dst)
        print(f"✅ Uploaded: {local_path} → {hdfs_path}")
    
    def get(self, hdfs_path: str, local_path: str, overwrite: bool = True):
        """
        Download file from HDFS to local.
        
        Usage:
            hdfs.get("/user/jovyan/file.csv", "/home/jovyan/download.csv")
        """
        src = self._Path(hdfs_path)
        dst = self._Path(local_path)
        
        if not self._fs.exists(src):
            print(f"HDFS file not found: {hdfs_path}")
            return
        
        # Ensure parent dir exists locally
        import os
        os.makedirs(os.path.dirname(local_path) or ".", exist_ok=True)
        
        self._fs.copyToLocalFile(False, src, dst, overwrite)
        print(f"✅ Downloaded: {hdfs_path} → {local_path}")
    
    def write(self, hdfs_path: str, data: str, overwrite: bool = True):
        """
        Write string data directly to HDFS file.
        
        Usage:
            hdfs.write("/user/jovyan/file.txt", "Hello, HDFS!")
            hdfs.write("/user/jovyan/file.txt", "line1\nline2\nline3")
        """
        dst = self._Path(hdfs_path)
        self._fs.mkdirs(dst.getParent())
        
        if not overwrite and self._fs.exists(dst):
            print(f"File already exists (use overwrite=True): {hdfs_path}")
            return
        
        out = self._fs.create(dst, overwrite)
        try:
            out.write(bytearray(data, "utf-8"))
            print(f"✅ Written to: {hdfs_path}")
        finally:
            out.close()
    
    def append(self, hdfs_path: str, data: str):
        """Append string data to HDFS file."""
        dst = self._Path(hdfs_path)
        
        if not self._fs.exists(dst):
            # If file doesn't exist, create it
            self.write(hdfs_path, data, overwrite=True)
            return
        
        # Append
        out = self._fs.append(dst)
        try:
            out.write(bytearray(data, "utf-8"))
            print(f"✅ Appended to: {hdfs_path}")
        finally:
            out.close()
    
    # ═══════════════════════════════════════════
    #  FILE OPERATIONS
    # ═══════════════════════════════════════════
    
    def cp(self, src: str, dst: str, overwrite: bool = True):
        """
        Copy file within HDFS.
        
        Usage:
            hdfs.cp("/user/jovyan/file.csv", "/user/jovyan/backup/file.csv")
        """
        src_p = self._Path(src)
        dst_p = self._Path(dst)
        
        if not self._fs.exists(src_p):
            print(f"Source not found: {src}")
            return
        
        if self._fs.isDirectory(src_p):
            self._fs.mkdirs(dst_p)
            self._jvm.org.apache.hadoop.fs.FileUtil.copy(
                self._fs, src_p, self._fs, dst_p, False, overwrite, self._conf
            )
        else:
            self._fs.mkdirs(dst_p.getParent())
            self._jvm.org.apache.hadoop.fs.FileUtil.copy(
                self._fs, src_p, self._fs, dst_p, False, overwrite, self._conf
            )
        print(f"✅ Copied: {src} → {dst}")
    
    def mv(self, src: str, dst: str):
        """
        Move/rename file in HDFS.
        
        Usage:
            hdfs.mv("/user/jovyan/old.csv", "/user/jovyan/new.csv")
        """
        src_p = self._Path(src)
        dst_p = self._Path(dst)
        
        if not self._fs.exists(src_p):
            print(f"Source not found: {src}")
            return
        
        self._fs.mkdirs(dst_p.getParent())
        success = self._fs.rename(src_p, dst_p)
        if success:
            print(f"✅ Moved: {src} → {dst}")
        else:
            print(f"❌ Move failed: {src} → {dst}")
    
    def rm(self, path: str, recursive: bool = False):
        """
        Delete file or directory.
        
        Usage:
            hdfs.rm("/user/jovyan/file.csv")
            hdfs.rm("/user/jovyan/folder", recursive=True)
        """
        p = self._Path(path)
        
        if not self._fs.exists(p):
            print(f"Path not found: {path}")
            return
        
        success = self._fs.delete(p, recursive)
        if success:
            print(f"✅ Deleted: {path}")
        else:
            print(f"❌ Delete failed: {path}")
    
    # ═══════════════════════════════════════════
    #  DIRECTORIES
    # ═══════════════════════════════════════════
    
    def mkdir(self, path: str, parents: bool = True):
        """
        Create directory.
        
        Usage:
            hdfs.mkdir("/user/jovyan/new_folder")
            hdfs.mkdir("/user/jovyan/a/b/c/d")      # creates all parents
        """
        p = self._Path(path)
        if parents:
            success = self._fs.mkdirs(p)
        else:
            success = self._fs.mkdir(p)
        if success or self._fs.exists(p):
            print(f"✅ Created: {path}")
        else:
            print(f"❌ Failed to create: {path}")
    
    # ═══════════════════════════════════════════
    #  DISK USAGE
    # ═══════════════════════════════════════════
    
    def du(self, path: str = "/", human: bool = False, summary: bool = False):
        """
        Show disk usage.
        
        Usage:
            hdfs.du("/user/jovyan")
            hdfs.du("/user/jovyan", human=True)
            hdfs.du("/user/jovyan", summary=True)
        """
        p = self._Path(path)
        
        if not self._fs.exists(p):
            print(f"Path not found: {path}")
            return
        
        if self._fs.isFile(p):
            s = self._fs.getFileStatus(p)
            size = self._human_size(s.getLen()) if human else s.getLen()
            print(f"{size}  {path}")
        else:
            summary_obj = self._fs.getContentSummary(p)
            if summary:
                # Just summary
                total = summary_obj.getLength()
                files = summary_obj.getFileCount()
                dirs = summary_obj.getDirectoryCount()
                print(f"DIR:   {path}")
                print(f"  Total Size:    {self._human_size(total) if human else total}")
                print(f"  Files:         {files}")
                print(f"  Directories:   {dirs}")
            else:
                # Per-item listing
                status = self._fs.listStatus(p)
                total = 0
                for s in status:
                    size = s.getLen()
                    total += size
                    size_str = self._human_size(size) if human else size
                    print(f"{size_str:>15}  {s.getPath()}")
                
                # Total row
                total_str = self._human_size(total) if human else total
                print(f"{total_str:>15}  {path} (Total)")
    
    def df(self, human: bool = False):
        """
        Show HDFS filesystem capacity info.
        
        Usage:
            hdfs.df()
            hdfs.df(human=True)
        """
        fs_stats = self._fs.getStatus()
        capacity = fs_stats.getCapacity()
        used = fs_stats.getUsed()
        remaining = fs_stats.getRemaining()
        percent_used = (used / capacity * 100) if capacity > 0 else 0
        
        print(f"Filesystem:  hdfs://")
        print(f"Total:       {self._human_size(capacity) if human else capacity}")
        print(f"Used:        {self._human_size(used) if human else used} ({percent_used:.1f}%)")
        print(f"Remaining:   {self._human_size(remaining) if human else remaining}")
        print(f"Percent Used: {'█' * int(percent_used / 5)}{'░' * (20 - int(percent_used / 5))} {percent_used:.1f}%")
    
    def count(self, path: str):
        """
        Count directories, files, and bytes.
        
        Usage:
            hdfs.count("/user/jovyan")
        """
        p = self._Path(path)
        summary = self._fs.getContentSummary(p)
        print(f"DIR_COUNT  FILE_COUNT  CONTENT_SIZE  PATHNAME")
        print(f"{summary.getDirectoryCount():>10}  {summary.getFileCount():>10}  "
              f"{summary.getLength():>13}  {path}")
    
    # ═══════════════════════════════════════════
    #  PERMISSIONS
    # ═══════════════════════════════════════════
    
    def chmod(self, path: str, mode: str, recursive: bool = False):
        """
        Change file permissions.
        
        Usage:
            hdfs.chmod("/user/jovyan/file.csv", "755")
            hdfs.chmod("/user/jovyan/folder", "755", recursive=True)
        """
        p = self._Path(path)
        
        if not self._fs.exists(p):
            print(f"Path not found: {path}")
            return
        
        # Parse permission string (e.g., "755" → 0o755)
        perm = int(mode, 8)
        
        if recursive and self._fs.isDirectory(p):
            self._chmod_recursive(p, perm)
        else:
            new_perm = self._jvm.org.apache.hadoop.fs.permission.FsPermission(mode)
            self._fs.setPermission(p, new_perm)
        
        print(f"✅ Permissions set: {mode} on {path}")
    
    def _chmod_recursive(self, path, perm):
        # Convert back to octal string for FsPermission constructor
        mode_str = oct(perm)[2:]  # Remove '0o' prefix
        new_perm = self._jvm.org.apache.hadoop.fs.permission.FsPermission(mode_str)
        for s in self._fs.listStatus(path):
            p = s.getPath()
            self._fs.setPermission(p, new_perm)
            if s.isDirectory():
                self._chmod_recursive(p, perm)
    
    def chown(self, path: str, owner: str = None, group: str = None, recursive: bool = False):
        """
        Change file ownership.
        
        Usage:
            hdfs.chown("/user/jovyan/file.csv", "jovyan")
            hdfs.chown("/user/jovyan/file.csv", "jovyan", "users")
            hdfs.chown("/user/jovyan/folder", "jovyan", recursive=True)
        """
        p = self._Path(path)
        
        if not self._fs.exists(p):
            print(f"Path not found: {path}")
            return
        
        if recursive and self._fs.isDirectory(p):
            self._chown_recursive(p, owner, group)
        else:
            self._fs.setOwner(p, owner, group)
        
        print(f"✅ Ownership changed: {path}")
    
    def _chown_recursive(self, path, owner, group):
        for s in self._fs.listStatus(path):
            p = s.getPath()
            self._fs.setOwner(p, owner, group)
            if s.isDirectory():
                self._chown_recursive(p, owner, group)
    
    # ═══════════════════════════════════════════
    #  HELPERS
    # ═══════════════════════════════════════════
    
    def _human_size(self, n: int) -> str:
        """Convert bytes to human-readable string."""
        if n is None or n == 0:
            return "0B"
        n = float(n)
        for unit in ["B", "KB", "MB", "GB", "TB", "PB"]:
            if abs(n) < 1024.0:
                return f"{n:.1f}{unit}"
            n /= 1024.0
        return f"{n:.1f}PB"
    
    def _octal_to_perms(self, mode: int) -> str:
        """Convert numeric permission to rwx string."""
        # Extract the last 9 bits (user, group, other permissions)
        mode = mode & 0o777
        perms = ""
        for i in range(3):
            # Extract 3 bits at a time (from high to low)
            shift = (2 - i) * 3
            val = (mode >> shift) & 0o7
            perms += "r" if (val & 0o4) else "-"
            perms += "w" if (val & 0o2) else "-"
            perms += "x" if (val & 0o1) else "-"
        return perms
    
    def help(self):
        """Print all available commands."""
        print("""
╔══════════════════════════════════════════════════════════════════╗
║               🗂️  HDFS PySpark Wrapper Commands                 ║
╠══════════════════════════════════════════════════════════════════╣
║                                                                  ║
║  NAVIGATION                                                      ║
║  ─────────────────────────────────────────────────────────────  ║
║  hdfs.ls(path, recursive, human)   List directory                ║
║  hdfs.exists(path)                 Check if path exists          ║
║  hdfs.info(path)                   Show file/dir info            ║
║                                                                  ║
║  READING                                                         ║
║  ─────────────────────────────────────────────────────────────  ║
║  hdfs.cat(path, max_lines)         Display file contents         ║
║  hdfs.head(path, n)                First N lines                 ║
║  hdfs.tail(path, n)                Last N lines                  ║
║  hdfs.read(path, start, length)    Read raw bytes                ║
║                                                                  ║
║  WRITING & TRANSFERRING                                         ║
║  ─────────────────────────────────────────────────────────────  ║
║  hdfs.put(local, hdfs)             Upload local → HDFS          ║
║  hdfs.get(hdfs, local)             Download HDFS → local        ║
║  hdfs.write(hdfs, data)            Write string to HDFS          ║
║  hdfs.append(hdfs, data)           Append string to HDFS         ║
║                                                                  ║
║  FILE OPERATIONS                                                 ║
║  ─────────────────────────────────────────────────────────────  ║
║  hdfs.cp(src, dst)                 Copy within HDFS              ║
║  hdfs.mv(src, dst)                 Move/rename                   ║
║  hdfs.rm(path, recursive)          Delete file/directory         ║
║  hdfs.mkdir(path)                  Create directory              ║
║                                                                  ║
║  DISK USAGE                                                      ║
║  ─────────────────────────────────────────────────────────────  ║
║  hdfs.du(path, human, summary)     Disk usage                    ║
║  hdfs.df(human)                    Filesystem capacity           ║
║  hdfs.count(path)                  Count dirs/files/bytes        ║
║                                                                  ║
║  PERMISSIONS                                                     ║
║  ─────────────────────────────────────────────────────────────  ║
║  hdfs.chmod(path, mode, recursive)  Change permissions           ║
║  hdfs.chown(path, owner, group, recursive)  Change ownership     ║
║                                                                  ║
║  UTILITY                                                         ║
║  ─────────────────────────────────────────────────────────────  ║
║  hdfs.help()                       Show this help                ║
║                                                                  ║
╚══════════════════════════════════════════════════════════════════╝
""")


# ─────────────────────────────────────────────
#  Register as IPython magic
# ─────────────────────────────────────────────

def hdfs_ex(line, cell, hdfs_wrapper):
    """
    Cell magic: %%hdfs command args
    
    Usage:
        %%hdfs ls /user/jovyan
        %%hdfs cat /user/jovyan/file.csv
        %%hdfs put /local/file.csv /user/jovyan/
    """
    parts = cell.strip().split()
    if not parts:
        hdfs_wrapper.help()
        return
    
    cmd = parts[0]
    args = parts[1:]
    args_str = " ".join(args)
    
    # Map commands to HDFS methods
    if cmd == "ls":
        recursive = "-R" in args or "-r" in args
        human = "-h" in args
        # Filter out flags for path
        path_args = [a for a in args if not a.startswith("-")]
        path = path_args[0] if path_args else "/"
        hdfs_wrapper.ls(path, recursive=recursive, human=human)
    
    elif cmd == "cat":
        path_args = [a for a in args if not a.startswith("-")]
        if path_args:
            hdfs_wrapper.cat(path_args[0])
        else:
            print("Usage: %%hdfs cat /path/to/file")
    
    elif cmd == "head":
        n = 10
        path_args = [a for a in args if not a.startswith("-") and not a.isdigit()]
        num_args = [a for a in args if a.isdigit()]
        if num_args:
            n = int(num_args[0])
        if path_args:
            hdfs_wrapper.head(path_args[0], n)
        else:
            print("Usage: %%hdfs head /path/to/file [n]")
    
    elif cmd == "tail":
        n = 10
        path_args = [a for a in args if not a.startswith("-") and not a.isdigit()]
        num_args = [a for a in args if a.isdigit()]
        if num_args:
            n = int(num_args[0])
        if path_args:
            hdfs_wrapper.tail(path_args[0], n)
        else:
            print("Usage: %%hdfs tail /path/to/file [n]")
    
    elif cmd == "mkdir":
        path_args = [a for a in args if not a.startswith("-")]
        if path_args:
            hdfs_wrapper.mkdir(path_args[0])
        else:
            print("Usage: %%hdfs mkdir /path")
    
    elif cmd == "put":
        # put local_path hdfs_path
        path_args = [a for a in args if not a.startswith("-")]
        if len(path_args) >= 2:
            hdfs_wrapper.put(path_args[0], path_args[1])
        else:
            print("Usage: %%hdfs put /local/path /hdfs/path")
    
    elif cmd == "get":
        path_args = [a for a in args if not a.startswith("-")]
        if len(path_args) >= 2:
            hdfs_wrapper.get(path_args[0], path_args[1])
        else:
            print("Usage: %%hdfs get /hdfs/path /local/path")
    
    elif cmd == "cp":
        path_args = [a for a in args if not a.startswith("-")]
        if len(path_args) >= 2:
            hdfs_wrapper.cp(path_args[0], path_args[1])
        else:
            print("Usage: %%hdfs cp /src /dst")
    
    elif cmd == "mv":
        path_args = [a for a in args if not a.startswith("-")]
        if len(path_args) >= 2:
            hdfs_wrapper.mv(path_args[0], path_args[1])
        else:
            print("Usage: %%hdfs mv /src /dst")
    
    elif cmd == "rm":
        recursive = "-r" in args or "-R" in args
        path_args = [a for a in args if not a.startswith("-")]
        if path_args:
            hdfs_wrapper.rm(path_args[0], recursive=recursive)
        else:
            print("Usage: %%hdfs rm [-r] /path")
    
    elif cmd == "du":
        human = "-h" in args
        summary = "-s" in args
        path_args = [a for a in args if not a.startswith("-")]
        path = path_args[0] if path_args else "/"
        hdfs_wrapper.du(path, human=human, summary=summary)
    
    elif cmd == "df":
        human = "-h" in args
        hdfs_wrapper.df(human=human)
    
    elif cmd == "count":
        path_args = [a for a in args if not a.startswith("-")]
        path = path_args[0] if path_args else "/"
        hdfs_wrapper.count(path)
    
    elif cmd == "chmod":
        recursive = "-R" in args or "-r" in args
        other_args = [a for a in args if not a.startswith("-")]
        if len(other_args) >= 2:
            mode = other_args[0]
            path = other_args[1]
            hdfs_wrapper.chmod(path, mode, recursive=recursive)
        else:
            print("Usage: %%hdfs chmod [-R] 755 /path")
    
    elif cmd == "chown":
        recursive = "-R" in args or "-r" in args
        other_args = [a for a in args if not a.startswith("-")]
        if len(other_args) >= 2:
            owner_group = other_args[0]
            owner = owner_group.split(":")[0] if ":" in owner_group else owner_group
            group = owner_group.split(":")[1] if ":" in owner_group else None
            path = other_args[1]
            hdfs_wrapper.chown(path, owner=owner, group=group, recursive=recursive)
        else:
            print("Usage: %%hdfs chown [-R] user[:group] /path")
    
    elif cmd == "test":
        path_args = [a for a in args if not a.startswith("-")]
        if path_args:
            exists = hdfs_wrapper.exists(path_args[0])
            print(f"{'✅' if exists else '❌'} {path_args[0]}")
        else:
            print("Usage: %%hdfs test /path")
    
    elif cmd == "info":
        path_args = [a for a in args if not a.startswith("-")]
        path = path_args[0] if path_args else "/"
        hdfs_wrapper.info(path)
    
    elif cmd in ("help", "?"):
        hdfs_wrapper.help()
    
    else:
        print(f"❌ Unknown command: {cmd}")
        print("   Type '%%hdfs help' for available commands.")


def sql_ex(line, cell, spark):
    df = spark.sql(cell)

    if line.startswith("var="):
        var_name = line.split("=", 1)[1].strip()
        get_ipython().user_ns[var_name] = df
        print(f"Stored Spark DataFrame in '{var_name}'")
        return
    
    if "schema" in line:
        return df.printSchema()

    elif "explain" in line:
        return df.explain()

    elif "spark" in line:
        return df.show()

    else:
        return df.toPandas()


def init(spark):
    from IPython import get_ipython
    
    spark = get_ipython().user_ns.get("spark")
    
    hdfs_wrapper = HDFS(spark)
    get_ipython().user_ns["hdfs"] = hdfs_wrapper
    
    hdfs = partial(hdfs_ex, hdfs_wrapper=hdfs_wrapper)
    sql = partial(sql_ex, spark=spark)
    
    register_cell_magic('sql')(sql)
    register_cell_magic('hdfs')(hdfs)

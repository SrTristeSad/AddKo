"""Compatibility layer for addons that import the zipfile_path backport.

Modern CPython already provides zipfile.Path. Several Kodi addons still depend
on the small compatibility package named ``zipfile_path``. Expose the modern
stdlib implementation under the historical module name so those addons can run
without bundling a duplicate backport.
"""

from zipfile import Path

__all__ = ["Path"]

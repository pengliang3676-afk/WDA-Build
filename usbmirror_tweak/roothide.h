#ifndef USBMIRROR_ROOTHIDE_COMPAT_H
#define USBMIRROR_ROOTHIDE_COMPAT_H

// ZXTouch only uses jbroot() while locating an optional shell.  Dopamine
// rootless has stable /var/jb fallbacks in Common.xm, so returning the input
// path here keeps the capture/touch subset independent of RootHide headers.
static inline const char *jbroot(const char *path)
{
    return path;
}

#endif

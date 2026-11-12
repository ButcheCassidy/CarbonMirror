package com.genymobile.scrcpy.wrappers;

import com.genymobile.scrcpy.FakeContext;

import android.content.ClipData;
import android.content.ClipDescription;
import android.content.Context;

public final class ClipboardManager {
    private final android.content.ClipboardManager manager;

    static ClipboardManager create() {
        android.content.ClipboardManager manager = (android.content.ClipboardManager) FakeContext.get().getSystemService(Context.CLIPBOARD_SERVICE);
        if (manager == null) {
            // Some devices have no clipboard manager
            // <https://github.com/Genymobile/scrcpy/issues/1440>
            // <https://github.com/Genymobile/scrcpy/issues/1556>
            return null;
        }
        return new ClipboardManager(manager);
    }

    private ClipboardManager(android.content.ClipboardManager manager) {
        this.manager = manager;
    }

    public CharSequence getText() {
        ClipData clipData = manager.getPrimaryClip();
        if (clipData == null || clipData.getItemCount() == 0) {
            return null;
        }
        // CarbonMirror: plain text only — URIs, intents and other clip types are never read or sent
        ClipDescription description = clipData.getDescription();
        if (description == null || !(description.hasMimeType(ClipDescription.MIMETYPE_TEXT_PLAIN)
                || description.hasMimeType(ClipDescription.MIMETYPE_TEXT_HTML))) {
            return null;
        }
        // CarbonMirror: clips marked sensitive (passwords from password managers, Android 13+) never leave the phone
        android.os.PersistableBundle extras = description.getExtras();
        if (extras != null && extras.getBoolean(ClipDescription.EXTRA_IS_SENSITIVE)) {
            return null;
        }
        CharSequence text = clipData.getItemAt(0).getText();
        return text == null ? null : text.toString();
    }

    public boolean setText(CharSequence text) {
        ClipData clipData = ClipData.newPlainText(null, text);
        manager.setPrimaryClip(clipData);
        return true;
    }

    public void addPrimaryClipChangedListener(android.content.ClipboardManager.OnPrimaryClipChangedListener listener) {
        manager.addPrimaryClipChangedListener(listener);
    }
}

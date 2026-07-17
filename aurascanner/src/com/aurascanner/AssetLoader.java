package com.aurascanner;

import android.content.res.AssetManager;
import java.io.File;
import java.io.FileOutputStream;
import java.io.IOException;
import java.io.InputStream;
import java.io.OutputStream;

/**
 * Hydrates APK assets/www/ into the app's private files dir on first run.
 * Required because Android WebView's file:// scheme cannot serve from
 * the read-only APK asset bundle directly when service workers /
 * cache APIs are in play.
 */
public final class AssetLoader {

    private AssetLoader() {}

    public static void copyAssetsToFiles(AssetManager assets, File filesDir) {
        File wwwDir = new File(filesDir, "www");
        if (new File(wwwDir, "index.html").exists()) {
            return; // already hydrated
        }
        if (!wwwDir.mkdirs() && !wwwDir.isDirectory()) {
            throw new RuntimeException("Cannot create " + wwwDir);
        }
        copyDir(assets, "www", wwwDir);
    }

    private static void copyDir(AssetManager assets, String assetPath, File outDir) {
        try {
            String[] children = assets.list(assetPath);
            if (children == null || children.length == 0) {
                // treat as file
                copyFile(assets, assetPath, new File(outDir, baseName(assetPath)));
                return;
            }
            for (String child : children) {
                String childAsset = assetPath + "/" + child;
                File childOut = new File(outDir, child);
                String[] grandchildren = assets.list(childAsset);
                if (grandchildren != null && grandchildren.length > 0) {
                    if (!childOut.mkdirs() && !childOut.isDirectory()) {
                        throw new IOException("mkdirs failed: " + childOut);
                    }
                    copyDir(assets, childAsset, childOut);
                } else {
                    copyFile(assets, childAsset, childOut);
                }
            }
        } catch (IOException e) {
            throw new RuntimeException("Asset copy failed for " + assetPath, e);
        }
    }

    private static void copyFile(AssetManager assets, String assetPath, File outFile) throws IOException {
        try (InputStream in = assets.open(assetPath);
             OutputStream out = new FileOutputStream(outFile)) {
            byte[] buf = new byte[8192];
            int n;
            while ((n = in.read(buf)) > 0) {
                out.write(buf, 0, n);
            }
        }
    }

    private static String baseName(String path) {
        int slash = path.lastIndexOf('/');
        return slash < 0 ? path : path.substring(slash + 1);
    }
}

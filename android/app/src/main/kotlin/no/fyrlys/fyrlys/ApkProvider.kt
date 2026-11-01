package no.fyrlys.fyrlys

import android.content.ContentProvider
import android.content.ContentValues
import android.content.Context
import android.database.Cursor
import android.database.MatrixCursor
import android.net.Uri
import android.os.ParcelFileDescriptor
import android.provider.OpenableColumns
import java.io.File
import java.io.FileNotFoundException

/**
 * Gir Android sin installering lesetilgang til oppdateringen Fyrlys har lastet ned (en content://-adresse; Android
 * godtar ikke filstier fra andre apper). Bare filer i Fyrlys sin mappe «oppdatering», bare lesing, og bare når
 * Fyrlys gir lov for én adresse (grantUriPermissions, provideren er ikke eksportert).
 */
class ApkProvider : ContentProvider() {
    companion object {
        const val APK = "application/vnd.android.package-archive"

        /** Mappen oppdateringene lastes ned til (getApplicationSupportDirectory()/oppdatering i Dart). */
        fun base(context: Context): File = File(context.filesDir, "oppdatering").canonicalFile

        /** [file] når den ligger i [base] og finnes, ellers null. */
        fun fileIn(context: Context, file: File): File? {
            val base = base(context)
            val f = file.canonicalFile
            return if (f.path.startsWith(base.path + File.separator) && f.isFile) f else null
        }
    }

    override fun onCreate(): Boolean = true

    private fun fileFor(uri: Uri): File? {
        val context = context ?: return null
        val path = uri.path ?: return null
        return fileIn(context, File(base(context), path.trimStart('/')))
    }

    override fun openFile(uri: Uri, mode: String): ParcelFileDescriptor? {
        if (mode != "r") throw SecurityException("bare lesing")
        val file = fileFor(uri) ?: throw FileNotFoundException(uri.toString())
        return ParcelFileDescriptor.open(file, ParcelFileDescriptor.MODE_READ_ONLY)
    }

    override fun getType(uri: Uri): String = APK

    override fun query(
        uri: Uri,
        projection: Array<out String>?,
        selection: String?,
        selectionArgs: Array<out String>?,
        sortOrder: String?
    ): Cursor? {
        val file = fileFor(uri) ?: return null
        val cursor = MatrixCursor(arrayOf(OpenableColumns.DISPLAY_NAME, OpenableColumns.SIZE))
        cursor.addRow(arrayOf<Any>(file.name, file.length()))
        return cursor
    }

    override fun insert(uri: Uri, values: ContentValues?): Uri? = null

    override fun delete(uri: Uri, selection: String?, selectionArgs: Array<out String>?): Int = 0

    override fun update(uri: Uri, values: ContentValues?, selection: String?, selectionArgs: Array<out String>?): Int = 0
}

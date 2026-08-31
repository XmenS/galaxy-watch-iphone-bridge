package dev.galaxyhealthbridge.wearos.data

import android.content.Context
import androidx.room.ColumnInfo
import androidx.room.Dao
import androidx.room.Database
import androidx.room.Entity
import androidx.room.Index
import androidx.room.PrimaryKey
import androidx.room.Query
import androidx.room.Room
import androidx.room.RoomDatabase
import dev.galaxyhealthbridge.wearos.ble.Sample
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.withContext

@Entity(
    tableName = "samples",
    indices = [Index(value = ["uid"], unique = true), Index(value = ["startMs"])],
)
data class SampleRow(
    @PrimaryKey(autoGenerate = true) val id: Long = 0,
    val uid: String,
    val type: String,
    val value: Double?,
    val unit: String?,
    @ColumnInfo(name = "startMs") val startMs: Long,
    @ColumnInfo(name = "endMs") val endMs: Long,
) {
    fun toSample() = Sample(uid = uid, t = type, v = value, u = unit, startMs = startMs, endMs = endMs)
}

@Dao
interface SampleDao {
    // Insert-or-ignore for per-event samples (HR per second, etc.) where each
    // uid is unique and we want at-most-once semantics.
    @Query("INSERT OR IGNORE INTO samples (uid, type, value, unit, startMs, endMs) VALUES (:uid,:type,:value,:unit,:startMs,:endMs)")
    suspend fun insertIfAbsent(uid: String, type: String, value: Double?, unit: String?, startMs: Long, endMs: Long)

    // Insert-or-replace for idempotent total samples (one per metric per day),
    // so updates to today's running total overwrite the previous row.
    @Query("INSERT OR REPLACE INTO samples (uid, type, value, unit, startMs, endMs) VALUES (:uid,:type,:value,:unit,:startMs,:endMs)")
    suspend fun upsert(uid: String, type: String, value: Double?, unit: String?, startMs: Long, endMs: Long)

    @Query("SELECT * FROM samples WHERE startMs > :sinceMs ORDER BY startMs ASC LIMIT :limit")
    suspend fun fetchSince(sinceMs: Long, limit: Int): List<SampleRow>

    @Query("SELECT COUNT(*) FROM samples WHERE startMs > :sinceMs")
    suspend fun countSince(sinceMs: Long): Int

    @Query("SELECT MAX(startMs) FROM samples")
    suspend fun newest(): Long?

    // Reset hook: lets the SyncService prune state on start / on iPhone reset.
    @Query("DELETE FROM samples")
    suspend fun deleteAll()

    @Query("DELETE FROM samples WHERE startMs < :olderThanMs")
    suspend fun deleteOlderThan(olderThanMs: Long)

    @Query("DELETE FROM samples WHERE startMs <= :cursorMs")
    suspend fun deleteThrough(cursorMs: Long): Int
}

@Database(entities = [SampleRow::class], version = 1, exportSchema = false)
abstract class AppDb : RoomDatabase() {
    abstract fun samples(): SampleDao
    companion object {
        @Volatile private var INSTANCE: AppDb? = null
        fun get(ctx: Context): AppDb = INSTANCE ?: synchronized(this) {
            INSTANCE ?: Room.databaseBuilder(ctx, AppDb::class.java, "ghb.db")
                .fallbackToDestructiveMigration()
                .build().also { INSTANCE = it }
        }
    }
}

class SampleStore(private val ctx: Context) {
    private val dao get() = AppDb.get(ctx).samples()

    suspend fun add(uid: String, type: String, value: Double?, unit: String?, startMs: Long, endMs: Long) =
        withContext(Dispatchers.IO) { dao.insertIfAbsent(uid, type, value, unit, startMs, endMs) }

    suspend fun upsert(uid: String, type: String, value: Double?, unit: String?, startMs: Long, endMs: Long) =
        withContext(Dispatchers.IO) { dao.upsert(uid, type, value, unit, startMs, endMs) }

    suspend fun page(sinceMs: Long, limit: Int): List<Sample> =
        withContext(Dispatchers.IO) { dao.fetchSince(sinceMs, limit).map { it.toSample() } }

    suspend fun pending(sinceMs: Long): Int = withContext(Dispatchers.IO) { dao.countSince(sinceMs) }
    suspend fun newest(): Long = withContext(Dispatchers.IO) { dao.newest() ?: 0L }

    suspend fun clear() = withContext(Dispatchers.IO) { dao.deleteAll() }
    suspend fun pruneOlderThan(olderThanMs: Long) =
        withContext(Dispatchers.IO) { dao.deleteOlderThan(olderThanMs) }

    suspend fun pruneThrough(cursorMs: Long): Int =
        withContext(Dispatchers.IO) { dao.deleteThrough(cursorMs) }
}

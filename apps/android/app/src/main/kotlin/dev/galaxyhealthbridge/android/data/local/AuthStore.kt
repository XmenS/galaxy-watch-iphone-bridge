package dev.galaxyhealthbridge.android.data.local

import androidx.datastore.core.DataStore
import androidx.datastore.preferences.core.Preferences
import androidx.datastore.preferences.core.edit
import androidx.datastore.preferences.core.stringPreferencesKey
import kotlinx.coroutines.flow.first
import kotlinx.coroutines.flow.map
import javax.inject.Inject
import javax.inject.Singleton

@Singleton
class AuthStore @Inject constructor(
    private val ds: DataStore<Preferences>,
) {
    private object Keys {
        val ACCESS = stringPreferencesKey("access_token")
        val REFRESH = stringPreferencesKey("refresh_token")
        val INSTALL_ID = stringPreferencesKey("install_id")
        val SYNC_CURSOR = stringPreferencesKey("sync_cursor")
    }

    suspend fun installId(): String {
        val v = ds.data.map { it[Keys.INSTALL_ID] }.first()
        if (v != null) return v
        val n = java.util.UUID.randomUUID().toString()
        ds.edit { it[Keys.INSTALL_ID] = n }
        return n
    }

    suspend fun accessToken(): String? = ds.data.map { it[Keys.ACCESS] }.first()
    suspend fun refreshToken(): String? = ds.data.map { it[Keys.REFRESH] }.first()
    suspend fun cursor(): String? = ds.data.map { it[Keys.SYNC_CURSOR] }.first()

    suspend fun setTokens(access: String, refresh: String) = ds.edit {
        it[Keys.ACCESS] = access
        it[Keys.REFRESH] = refresh
    }

    suspend fun setCursor(c: String) = ds.edit { it[Keys.SYNC_CURSOR] = c }

    suspend fun clear() = ds.edit {
        it.remove(Keys.ACCESS); it.remove(Keys.REFRESH); it.remove(Keys.SYNC_CURSOR)
    }
}

package com.wearos.ancsbridge.ancs

/** ANCS exposes an app identifier but not the original application artwork. */
object AppIconMapper {
    fun getIconResId(appIdentifier: String?, categoryId: Int): Int = when (categoryId) {
        1, 2, 3 -> android.R.drawable.sym_action_call
        4 -> android.R.drawable.sym_action_email
        6 -> android.R.drawable.ic_menu_my_calendar
        else -> android.R.drawable.ic_dialog_info
    }
}

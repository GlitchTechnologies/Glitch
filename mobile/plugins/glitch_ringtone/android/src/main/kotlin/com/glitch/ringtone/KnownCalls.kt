package com.glitch.ringtone

object KnownCalls {

    private const val CAPACITY = 64

    private val ids = LinkedHashSet<Long>()

    /**
     * Первое ли это известие о звонке [callId]. Проверка и запись — одним
     * действием: сокет и пуш могут принести один и тот же вызов одновременно.
     */
    @Synchronized
    fun claim(callId: Long): Boolean {
        if (!ids.add(callId)) return false
        if (ids.size > CAPACITY) {
            ids.remove(ids.iterator().next())
        }
        return true
    }
}

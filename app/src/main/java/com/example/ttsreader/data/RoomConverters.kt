package com.example.ttsreader.data

import androidx.room.TypeConverter
import com.example.ttsreader.core.SourceType

class RoomConverters {
    @TypeConverter
    fun toSourceType(value: String): SourceType = SourceType.valueOf(value)

    @TypeConverter
    fun fromSourceType(value: SourceType): String = value.name
}

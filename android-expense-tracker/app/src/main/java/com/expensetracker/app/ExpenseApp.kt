package com.expensetracker.app

import android.app.Application
import com.expensetracker.app.data.AppDatabase
import com.expensetracker.app.data.ExpenseRepository

class ExpenseApp : Application() {

    lateinit var repository: ExpenseRepository
        private set

    override fun onCreate() {
        super.onCreate()
        val database = AppDatabase.getInstance(this)
        repository = ExpenseRepository(database.expenseDao())
    }
}

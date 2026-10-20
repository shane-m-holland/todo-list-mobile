package com.example.todo.di

import com.example.todo.BuildConfig
import com.example.todo.data.NetworkTodoRepository
import com.example.todo.data.TodoRepository
import com.example.todo.network.apis.TodosApi
import com.example.todo.network.client.TodoApiFactory
import dagger.Binds
import dagger.Module
import dagger.Provides
import dagger.hilt.InstallIn
import dagger.hilt.components.SingletonComponent
import javax.inject.Singleton
import okhttp3.OkHttpClient
import okhttp3.logging.HttpLoggingInterceptor

@Module
@InstallIn(SingletonComponent::class)
object NetworkModule {

    @Provides
    @Singleton
    fun okHttpClient(): OkHttpClient =
        OkHttpClient.Builder()
            .apply {
                if (BuildConfig.DEBUG) {
                    addInterceptor(HttpLoggingInterceptor().setLevel(HttpLoggingInterceptor.Level.BODY))
                }
            }
            .build()

    @Provides
    @Singleton
    fun todosApi(client: OkHttpClient): TodosApi = TodoApiFactory.create(BuildConfig.API_BASE_URL, client)
}

@Module
@InstallIn(SingletonComponent::class)
abstract class DataModule {
    @Binds
    abstract fun todoRepository(impl: NetworkTodoRepository): TodoRepository
}

<!--
  Copyright (C) 2026 Nethesis S.r.l.
  SPDX-License-Identifier: GPL-3.0-or-later
-->
<template>
  <cv-grid fullWidth>
    <cv-row>
      <cv-column class="page-title">
        <h2>{{ $t("settings.title") }}</h2>
      </cv-column>
    </cv-row>
    <cv-row v-if="error.getConfiguration">
      <cv-column>
        <NsInlineNotification
          kind="error"
          :title="$t('action.get-configuration')"
          :description="error.getConfiguration"
          :showCloseButton="false"
        />
      </cv-column>
    </cv-row>
    <cv-row v-if="isRouteMissing">
      <cv-column>
        <NsInlineNotification
          kind="warning"
          :title="$t('settings.no_route_title')"
          :description="$t('settings.no_route_description')"
          :showCloseButton="false"
        />
      </cv-column>
    </cv-row>
    <cv-row>
      <cv-column>
        <cv-tile light>
          <cv-form @submit.prevent="configureModule">
            <!-- web site -->
            <h4 class="mg-bottom-md">{{ $t("settings.web_site") }}</h4>
            <NsTextInput
              :label="$t('settings.host')"
              placeholder="www.example.org"
              v-model.trim="host"
              class="mg-bottom"
              :invalid-message="$t(error.host)"
              :disabled="stillLoading"
              ref="host"
            />
            <NsToggle
              value="letsEncrypt"
              :label="core.$t('apps_lets_encrypt.request_https_certificate')"
              v-model="isLetsEncryptEnabled"
              :disabled="stillLoading"
              class="mg-bottom"
            >
              <template #tooltip>
                <div class="mg-bottom-sm">
                  {{ core.$t("apps_lets_encrypt.lets_encrypt_tips") }}
                </div>
                <div class="mg-bottom-sm">
                  <cv-link @click="goToCertificates">
                    {{ core.$t("apps_lets_encrypt.go_to_tls_certificates") }}
                  </cv-link>
                </div>
              </template>
              <template slot="text-left">{{
                $t("settings.disabled")
              }}</template>
              <template slot="text-right">{{
                $t("settings.enabled")
              }}</template>
            </NsToggle>
            <NsInlineNotification
              v-if="isLetsEncryptCurrentlyEnabled && !isLetsEncryptEnabled"
              kind="warning"
              :title="
                core.$t('apps_lets_encrypt.lets_encrypt_disabled_warning')
              "
              :description="
                core.$t(
                  'apps_lets_encrypt.lets_encrypt_disabled_warning_description',
                  {
                    node: status.node_ui_name
                      ? status.node_ui_name
                      : status.node,
                  }
                )
              "
              :showCloseButton="false"
            />

            <!-- PHP -->
            <h4 class="mg-bottom-md mg-top">{{ $t("settings.php") }}</h4>
            <NsComboBox
              v-model="phpVersion"
              :title="$t('settings.php_version')"
              :label="$t('settings.choose_php_version')"
              :options="phpVersionOptions"
              :autoFilter="true"
              :autoHighlight="true"
              :invalid-message="$t(error.php_version)"
              :disabled="stillLoading"
              class="mg-bottom maxwidth"
              ref="php_version"
            />
            <NsInlineNotification
              v-if="phpVersion === '8.2'"
              kind="warning"
              :title="$t('settings.php_eol_title')"
              :description="$t('settings.php_eol_description')"
              :showCloseButton="false"
            />
            <!-- database -->
            <h4 class="mg-bottom-md mg-top">{{ $t("settings.database") }}</h4>
            <NsInlineNotification
              kind="info"
              :title="$t('settings.database_info_title')"
              :description="$t('settings.database_info_description')"
              :showCloseButton="false"
            />
            <NsTextInput
              :label="$t('settings.db_name')"
              placeholder="app"
              v-model.trim="dbName"
              :helper-text="$t('settings.db_name_helper')"
              :invalid-message="$t(error.db_name)"
              :disabled="stillLoading || isDbPasswordSet"
              class="mg-bottom maxwidth"
              ref="db_name"
            />
            <NsTextInput
              :label="$t('settings.db_user')"
              placeholder="app"
              v-model.trim="dbUser"
              :invalid-message="$t(error.db_user)"
              :disabled="stillLoading || isDbPasswordSet"
              class="mg-bottom maxwidth"
              ref="db_user"
            />
            <NsToggle
              v-if="isDbPasswordSet"
              key="changeDbPassword"
              value="changeDbPassword"
              :label="$t('settings.change_db_password')"
              v-model="isChangeDbPassword"
              :disabled="stillLoading"
              class="mg-bottom"
            >
              <template slot="text-left">{{
                $t("settings.disabled")
              }}</template>
              <template slot="text-right">{{
                $t("settings.enabled")
              }}</template>
            </NsToggle>
            <NsPasswordInput
              v-if="isDbPasswordActive"
              key="dbPassword"
              v-model="dbPassword"
              :newPasswordLabel="$t('settings.db_password')"
              :confirmPasswordLabel="$t('settings.db_password_confirm')"
              :newPasswordInvalidMessage="$t(error.db_password)"
              :confirmPasswordInvalidMessage="$t(error.db_password_confirm)"
              :passwordHideLabel="core.$t('password.hide_password')"
              :passwordShowLabel="core.$t('password.show_password')"
              :lengthLabel="core.$t('password.long_enough')"
              :lowercaseLabel="core.$t('password.lowercase_letter')"
              :uppercaseLabel="core.$t('password.uppercase_letter')"
              :numberLabel="core.$t('password.number')"
              :symbolLabel="core.$t('password.symbol')"
              :equalLabel="core.$t('password.equal')"
              :focus="focusDbPasswordField"
              :minLength="8"
              :disabled="stillLoading"
              @passwordValidation="onDbPasswordValidation"
              class="mg-bottom maxwidth"
            />
            <!-- MariaDB administrator and phpMyAdmin -->
            <h4 class="mg-bottom-md mg-top">
              {{ $t("settings.admin_account") }}
            </h4>
            <NsInlineNotification
              kind="info"
              :title="$t('settings.admin_account_info_title')"
              :description="$t('settings.admin_account_info_description')"
              :showCloseButton="false"
            />
            <NsToggle
              v-if="isAdminPasswordSet"
              key="changeAdminPassword"
              value="changeAdminPassword"
              :label="$t('settings.change_admin_password')"
              v-model="isChangeAdminPassword"
              :disabled="stillLoading"
              class="mg-bottom"
            >
              <template slot="text-left">{{
                $t("settings.disabled")
              }}</template>
              <template slot="text-right">{{
                $t("settings.enabled")
              }}</template>
            </NsToggle>
            <NsPasswordInput
              v-if="isAdminPasswordActive"
              key="adminPassword"
              v-model="adminPassword"
              :newPasswordLabel="$t('settings.admin_password')"
              :confirmPasswordLabel="$t('settings.admin_password_confirm')"
              :newPasswordInvalidMessage="$t(error.admin_password)"
              :confirmPasswordInvalidMessage="$t(error.admin_password_confirm)"
              :passwordHideLabel="core.$t('password.hide_password')"
              :passwordShowLabel="core.$t('password.show_password')"
              :lengthLabel="core.$t('password.long_enough')"
              :lowercaseLabel="core.$t('password.lowercase_letter')"
              :uppercaseLabel="core.$t('password.uppercase_letter')"
              :numberLabel="core.$t('password.number')"
              :symbolLabel="core.$t('password.symbol')"
              :equalLabel="core.$t('password.equal')"
              :focus="focusAdminPasswordField"
              :minLength="8"
              :disabled="stillLoading"
              @passwordValidation="onAdminPasswordValidation"
              class="mg-bottom maxwidth"
            />
            <NsToggle
              value="phpmyadminEnabled"
              :label="$t('settings.phpmyadmin')"
              v-model="isPhpmyadminEnabled"
              :disabled="stillLoading"
              class="mg-bottom"
            >
              <template #tooltip>
                {{ $t("settings.phpmyadmin_tooltip") }}
              </template>
              <template slot="text-left">{{
                $t("settings.disabled")
              }}</template>
              <template slot="text-right">{{
                $t("settings.enabled")
              }}</template>
            </NsToggle>

            <NsInlineNotification
              v-if="!loading.getConfiguration && !smarthost.enabled"
              kind="warning"
              :title="$t('settings.smarthost_disabled_title')"
              :description="$t('settings.smarthost_disabled_description')"
              :actionLabel="$t('settings.go_to_smarthost')"
              @action="goToSmarthost"
              :showCloseButton="false"
            />
            <cv-accordion ref="accordion" class="maxwidth mg-bottom mg-top">
              <cv-accordion-item :open="toggleAccordion[0]">
                <template slot="title">{{ $t("settings.advanced") }}</template>
                <template slot="content">
                  <h4 class="mg-bottom-md">{{ $t("settings.web_server") }}</h4>
                  <NsTextInput
                    :label="$t('settings.document_root')"
                    placeholder="public"
                    v-model.trim="documentRoot"
                    :helper-text="$t('settings.document_root_helper')"
                    :invalid-message="$t(error.document_root)"
                    :disabled="stillLoading"
                    class="mg-bottom maxwidth"
                    ref="document_root"
                  />
                  <NsComboBox
                    v-model="nginxPreset"
                    :title="$t('settings.nginx_preset')"
                    :label="$t('settings.choose_nginx_preset')"
                    :options="nginxPresetOptions"
                    :autoFilter="true"
                    :autoHighlight="true"
                    :invalid-message="$t(error.nginx_preset)"
                    :helper-text="$t('settings.nginx_preset_helper')"
                    :disabled="stillLoading"
                    class="mg-bottom maxwidth"
                    ref="nginx_preset"
                  />
                  <h4 class="mg-bottom-md mg-top">
                    {{ $t("settings.php_tuning") }}
                  </h4>
                  <!-- NsSlider reads invalidMessage only when it renders: the key re-renders it on a new error -->
                  <NsSlider
                    :label="$t('settings.php_memory_limit')"
                    min="128"
                    max="4096"
                    step="1"
                    minLabel=""
                    maxLabel=""
                    v-model="phpMemoryLimitMib"
                    :unitLabel="$t('settings.unit_mib')"
                    :invalidMessage="$t(error.php_memory_limit)"
                    :key="'php_memory_limit-' + error.php_memory_limit"
                    :disabled="stillLoading"
                    class="mg-bottom"
                    ref="php_memory_limit"
                  />
                  <NsSlider
                    :label="$t('settings.php_upload_max_filesize')"
                    min="2"
                    max="2048"
                    step="1"
                    minLabel=""
                    maxLabel=""
                    v-model="phpUploadMaxFilesizeMib"
                    :unitLabel="$t('settings.unit_mib')"
                    :invalidMessage="$t(error.php_upload_max_filesize)"
                    :key="
                      'php_upload_max_filesize-' + error.php_upload_max_filesize
                    "
                    :disabled="stillLoading"
                    class="mg-bottom"
                    ref="php_upload_max_filesize"
                  />
                  <NsSlider
                    :label="$t('settings.php_max_execution_time')"
                    min="1"
                    max="3600"
                    step="1"
                    minLabel=""
                    maxLabel=""
                    v-model="phpMaxExecutionTime"
                    :unitLabel="$t('settings.unit_seconds')"
                    :showUnlimited="true"
                    :isUnlimited="isExecutionTimeUnlimited"
                    :unlimitedLabel="$t('settings.unlimited')"
                    :limitedLabel="$t('settings.limited')"
                    @unlimited="isExecutionTimeUnlimited = $event"
                    :invalidMessage="$t(error.php_max_execution_time)"
                    :key="
                      'php_max_execution_time-' + error.php_max_execution_time
                    "
                    :disabled="stillLoading"
                    class="mg-bottom"
                    ref="php_max_execution_time"
                  />
                  <NsComboBox
                    v-model="phpTimezone"
                    :title="$t('settings.php_timezone')"
                    :label="$t('settings.choose_php_timezone')"
                    :options="timezoneOptions"
                    :autoFilter="true"
                    :autoHighlight="true"
                    :invalid-message="$t(error.php_timezone)"
                    :disabled="stillLoading"
                    class="mg-bottom maxwidth"
                    ref="php_timezone"
                  />
                  <NsSlider
                    :label="$t('settings.fpm_pm_max_children')"
                    min="1"
                    max="100"
                    step="1"
                    minLabel=""
                    maxLabel=""
                    v-model="fpmPmMaxChildren"
                    :invalidMessage="$t(error.fpm_pm_max_children)"
                    :key="'fpm_pm_max_children-' + error.fpm_pm_max_children"
                    :disabled="stillLoading"
                    class="mg-bottom"
                    ref="fpm_pm_max_children"
                  />

                  <!-- user domain -->
                  <h4 class="mg-bottom-md mg-top">
                    {{ $t("settings.user_domain_title") }}
                  </h4>
                  <NsInlineNotification
                    v-if="
                      !loading.getConfiguration && !userDomainOptions.length
                    "
                    kind="info"
                    :title="$t('settings.no_user_domain_title')"
                    :description="$t('settings.no_user_domain_description')"
                    :actionLabel="$t('settings.go_to_domains')"
                    @action="goToDomains"
                    :showCloseButton="false"
                  />
                  <template v-else>
                    <NsToggle
                      value="ldapEnabled"
                      :label="$t('settings.ldap_credentials')"
                      v-model="isLdapEnabled"
                      :disabled="stillLoading"
                      class="mg-bottom"
                    >
                      <template #tooltip>
                        {{ $t("settings.ldap_credentials_tooltip") }}
                      </template>
                      <template slot="text-left">{{
                        $t("settings.disabled")
                      }}</template>
                      <template slot="text-right">{{
                        $t("settings.enabled")
                      }}</template>
                    </NsToggle>
                    <NsComboBox
                      v-if="isLdapEnabled"
                      v-model="userDomain"
                      :title="$t('settings.user_domain')"
                      :label="$t('settings.choose_user_domain')"
                      :options="userDomainOptions"
                      :autoFilter="true"
                      :autoHighlight="true"
                      :invalid-message="$t(error.user_domain)"
                      :disabled="stillLoading"
                      class="mg-bottom maxwidth"
                      ref="user_domain"
                    />
                  </template>

                  <!-- mail -->
                  <h4 class="mg-bottom-md mg-top">{{ $t("settings.mail") }}</h4>
                  <NsInlineNotification
                    v-if="!loading.getConfiguration && smarthost.enabled"
                    kind="info"
                    :title="$t('settings.smarthost_enabled_title')"
                    :description="
                      $t('settings.smarthost_enabled_description', {
                        host: smarthost.host,
                      })
                    "
                    :showCloseButton="false"
                  />
                  <NsTextInput
                    :label="$t('settings.mail_from')"
                    :placeholder="mailFromPlaceholder"
                    v-model.trim="mailFrom"
                    :helper-text="$t('settings.mail_from_helper')"
                    :invalid-message="$t(error.mail_from)"
                    :disabled="stillLoading"
                    class="mg-bottom maxwidth"
                    ref="mail_from"
                  />

                  <!-- custom files -->
                  <h4 class="mg-bottom-md mg-top">
                    {{ $t("settings.custom_files") }}
                  </h4>
                  <NsInlineNotification
                    kind="info"
                    :title="$t('settings.custom_files_title')"
                    :description="
                      $t('settings.custom_files_description', {
                        instance: instanceName,
                      })
                    "
                    :showCloseButton="false"
                  />
                </template>
              </cv-accordion-item>
            </cv-accordion>
            <NsInlineNotification
              v-if="error.configureModule"
              kind="error"
              :title="$t('action.configure-module')"
              :description="error.configureModule"
              :showCloseButton="false"
            />
            <NsInlineNotification
              v-if="error.getStatus"
              kind="error"
              :title="$t('action.get-status')"
              :description="error.getStatus"
              :showCloseButton="false"
            />
            <NsInlineNotification
              v-if="validationErrorDetails.length"
              kind="error"
              :title="core.$t('apps_lets_encrypt.cannot_obtain_certificate')"
              :showCloseButton="false"
            >
              <template #description>
                <div class="flex flex-col gap-2">
                  <div
                    v-for="(detail, index) in validationErrorDetails"
                    :key="index"
                  >
                    {{ detail }}
                  </div>
                </div>
              </template>
            </NsInlineNotification>
            <NsButton
              kind="primary"
              :icon="Save20"
              :loading="loading.configureModule"
              :disabled="stillLoading"
              >{{ $t("settings.save") }}</NsButton
            >
          </cv-form>
        </cv-tile>
      </cv-column>
    </cv-row>
  </cv-grid>
</template>

<script>
import to from "await-to-js";
import { mapState } from "vuex";
import {
  QueryParamService,
  UtilService,
  TaskService,
  IconService,
  PageTitleService,
} from "@nethserver/ns8-ui-lib";

const PHP_VERSIONS = ["8.5", "8.4", "8.3", "8.2"];
// PHP size like 512M, 1G or 1536K, in whole MiB for the sliders
function sizeToMib(size) {
  const factor = { K: 1 / 1024, M: 1, G: 1024 }[size.slice(-1).toUpperCase()];
  return Math.max(1, Math.ceil(parseInt(size, 10) * factor));
}
const NAME_PATTERN = /^[A-Za-z0-9_]+$/;
// fields shown in the Advanced section
const ADVANCED_FIELDS = [
  "document_root",
  "nginx_preset",
  "php_memory_limit",
  "php_upload_max_filesize",
  "php_max_execution_time",
  "php_timezone",
  "fpm_pm_max_children",
  "user_domain",
  "mail_from",
];
const RESERVED_USERS = ["root", "admin", "mysql", "mariadb.sys", "healthcheck"];

export default {
  name: "Settings",
  mixins: [
    TaskService,
    IconService,
    UtilService,
    QueryParamService,
    PageTitleService,
  ],
  pageTitle() {
    return this.$t("settings.title") + " - " + this.appName;
  },
  data() {
    return {
      q: {
        page: "settings",
      },
      status: {},
      validationErrorDetails: [],
      urlCheckInterval: null,
      toggleAccordion: [false],
      host: "",
      configuredHost: "",
      isLetsEncryptEnabled: false,
      isLetsEncryptCurrentlyEnabled: false,
      isRouteConfigured: true,
      // empty until the configuration loads: NsComboBox shows the label only when the value changes
      nginxPreset: "",
      phpVersion: "",
      documentRoot: "",
      // the sliders hold plain numbers, sizes in MiB
      phpMemoryLimitMib: "512",
      phpUploadMaxFilesizeMib: "100",
      phpMaxExecutionTime: "600",
      isExecutionTimeUnlimited: false,
      phpTimezone: "",
      fpmPmMaxChildren: "10",
      dbName: "",
      dbUser: "",
      dbPassword: "",
      isDbPasswordSet: false,
      isChangeDbPassword: false,
      dbPasswordValidation: null,
      focusDbPasswordField: { element: "" },
      adminPassword: "",
      isAdminPasswordSet: false,
      isChangeAdminPassword: false,
      adminPasswordValidation: null,
      focusAdminPasswordField: { element: "" },
      isPhpmyadminEnabled: true,
      isLdapEnabled: false,
      userDomain: "",
      userDomains: [],
      smarthost: { enabled: false, host: "" },
      mailFrom: "",
      loading: {
        getConfiguration: false,
        configureModule: false,
        getStatus: false,
      },
      error: {
        getConfiguration: "",
        configureModule: "",
        getStatus: "",
        host: "",
        lets_encrypt: "",
        nginx_preset: "",
        document_root: "",
        php_version: "",
        php_memory_limit: "",
        php_upload_max_filesize: "",
        php_max_execution_time: "",
        php_timezone: "",
        fpm_pm_max_children: "",
        db_name: "",
        db_user: "",
        db_password: "",
        db_password_confirm: "",
        admin_password: "",
        admin_password_confirm: "",
        user_domain: "",
        mail_from: "",
      },
    };
  },
  computed: {
    ...mapState(["instanceName", "core", "appName"]),
    stillLoading() {
      return (
        this.loading.getConfiguration ||
        this.loading.configureModule ||
        this.loading.getStatus
      );
    },
    isDbPasswordActive() {
      // before the configuration loads every instance looks unconfigured
      if (this.loading.getConfiguration) {
        return false;
      }
      return !this.isDbPasswordSet || this.isChangeDbPassword;
    },
    isAdminPasswordActive() {
      if (this.loading.getConfiguration) {
        return false;
      }
      return !this.isAdminPasswordSet || this.isChangeAdminPassword;
    },
    isRouteMissing() {
      // a first configuration has no route yet: only a saved host without route means a clone
      return (
        !this.loading.getConfiguration &&
        this.configuredHost &&
        !this.isRouteConfigured
      );
    },
    nginxPresetOptions() {
      return ["generic", "wordpress"].map((value) => ({
        name: value,
        label: this.$t("settings.nginx_preset_" + value),
        value,
      }));
    },
    timezoneOptions() {
      // Older browsers have no list: offer UTC and the current zone only
      const zones = new Set(
        typeof Intl.supportedValuesOf === "function"
          ? Intl.supportedValuesOf("timeZone")
          : []
      );
      // UTC is not in the canonical list, and a zone set from the API may be missing too
      zones.add("UTC");
      if (this.phpTimezone) {
        zones.add(this.phpTimezone);
      }
      return [...zones].sort().map((zone) => ({
        name: zone,
        label: zone,
        value: zone,
      }));
    },
    phpVersionOptions() {
      return PHP_VERSIONS.map((value) => ({
        name: value,
        label: "PHP " + value,
        value,
      }));
    },
    userDomainOptions() {
      return this.userDomains.map((domain) => ({
        name: domain,
        label: domain,
        value: domain,
      }));
    },
    mailFromPlaceholder() {
      return "noreply@" + (this.host || "www.example.org");
    },
  },
  watch: {
    dbPassword() {
      this.error.db_password = "";
      this.error.db_password_confirm = "";
    },
    isChangeDbPassword() {
      this.dbPassword = "";
      this.error.db_password = "";
      this.error.db_password_confirm = "";
    },
    adminPassword() {
      this.error.admin_password = "";
      this.error.admin_password_confirm = "";
    },
    isChangeAdminPassword() {
      this.adminPassword = "";
      this.error.admin_password = "";
      this.error.admin_password_confirm = "";
    },
  },
  created() {
    this.getConfiguration();
    this.getStatus();
  },
  beforeRouteEnter(to, from, next) {
    next((vm) => {
      vm.watchQueryData(vm);
      vm.urlCheckInterval = vm.initUrlBindingForApp(vm, vm.q.page);
    });
  },
  beforeRouteLeave(to, from, next) {
    clearInterval(this.urlCheckInterval);
    next();
  },
  methods: {
    goToCertificates() {
      this.core.$router.push("/settings/tls-certificates");
    },
    goToSmarthost() {
      this.core.$router.push("/settings/smarthost");
    },
    goToDomains() {
      this.core.$router.push("/domains");
    },
    onDbPasswordValidation(validation) {
      this.dbPasswordValidation = validation;
    },
    onAdminPasswordValidation(validation) {
      this.adminPasswordValidation = validation;
    },
    async getStatus() {
      this.loading.getStatus = true;
      this.error.getStatus = "";
      const taskAction = "get-status";
      const eventId = this.getUuid();
      this.core.$root.$once(
        `${taskAction}-aborted-${eventId}`,
        this.getStatusAborted
      );
      this.core.$root.$once(
        `${taskAction}-completed-${eventId}`,
        this.getStatusCompleted
      );
      const res = await to(
        this.createModuleTaskForApp(this.instanceName, {
          action: taskAction,
          extra: {
            title: this.$t("action." + taskAction),
            isNotificationHidden: true,
            eventId,
          },
        })
      );
      const err = res[0];
      if (err) {
        console.error(`error creating task ${taskAction}`, err);
        this.error.getStatus = this.getErrorMessage(err);
        this.loading.getStatus = false;
        return;
      }
    },
    getStatusAborted(taskResult, taskContext) {
      console.error(`${taskContext.action} aborted`, taskResult);
      this.error.getStatus = this.$t("error.generic_error");
      this.loading.getStatus = false;
    },
    getStatusCompleted(taskContext, taskResult) {
      this.status = taskResult.output;
      this.loading.getStatus = false;
    },
    async getConfiguration() {
      this.loading.getConfiguration = true;
      this.error.getConfiguration = "";
      const taskAction = "get-configuration";
      const eventId = this.getUuid();
      this.core.$root.$once(
        `${taskAction}-aborted-${eventId}`,
        this.getConfigurationAborted
      );
      this.core.$root.$once(
        `${taskAction}-completed-${eventId}`,
        this.getConfigurationCompleted
      );
      const res = await to(
        this.createModuleTaskForApp(this.instanceName, {
          action: taskAction,
          extra: {
            title: this.$t("action." + taskAction),
            isNotificationHidden: true,
            eventId,
          },
        })
      );
      const err = res[0];
      if (err) {
        console.error(`error creating task ${taskAction}`, err);
        this.error.getConfiguration = this.getErrorMessage(err);
        this.loading.getConfiguration = false;
        return;
      }
    },
    getConfigurationAborted(taskResult, taskContext) {
      console.error(`${taskContext.action} aborted`, taskResult);
      this.error.getConfiguration = this.$t("error.generic_error");
      this.loading.getConfiguration = false;
    },
    getConfigurationCompleted(taskContext, taskResult) {
      const config = taskResult.output;
      this.host = config.host;
      this.configuredHost = config.host;
      this.isLetsEncryptEnabled = config.lets_encrypt;
      this.isLetsEncryptCurrentlyEnabled = config.lets_encrypt;
      this.isRouteConfigured = config.route_configured;
      this.nginxPreset = config.nginx_preset;
      this.documentRoot = config.document_root;
      this.phpVersion = config.php_version;
      this.phpMemoryLimitMib = String(sizeToMib(config.php_memory_limit));
      this.phpUploadMaxFilesizeMib = String(
        sizeToMib(config.php_upload_max_filesize)
      );
      this.isExecutionTimeUnlimited = config.php_max_execution_time === 0;
      this.phpMaxExecutionTime = String(config.php_max_execution_time || 600);
      this.phpTimezone = config.php_timezone;
      this.fpmPmMaxChildren = String(config.fpm_pm_max_children);
      this.dbName = config.db_name;
      this.dbUser = config.db_user;
      this.isDbPasswordSet = config.db_password_set;
      this.isAdminPasswordSet = config.admin_password_set;
      this.isPhpmyadminEnabled = config.phpmyadmin_enabled;
      this.userDomains = config.user_domains_list;
      // a deleted domain would block every save, show it as disabled
      const hasDomain = config.user_domains_list.includes(config.user_domain);
      this.isLdapEnabled = hasDomain;
      this.userDomain = hasDomain ? config.user_domain : "";
      this.smarthost = config.smarthost;
      this.mailFrom = config.mail_from;
      this.isChangeDbPassword = false;
      this.isChangeAdminPassword = false;
      this.dbPassword = "";
      this.adminPassword = "";

      this.loading.getConfiguration = false;
      this.focusElement("host");
    },
    isStrongPassword(v) {
      return (
        v &&
        v.isLengthOk &&
        v.isLowercaseOk &&
        v.isUppercaseOk &&
        v.isNumberOk &&
        v.isSymbolOk
      );
    },
    validateConfigureModule() {
      this.clearErrors(this);
      this.validationErrorDetails = [];
      let isValidationOk = true;

      const fail = (field, message, focus = true) => {
        this.error[field] = message;
        if (ADVANCED_FIELDS.includes(field)) {
          this.toggleAccordion = [true];
        }
        if (isValidationOk && focus) {
          this.focusElement(field);
        }
        isValidationOk = false;
      };

      if (!this.host) {
        fail("host", "common.required");
      }
      if (!this.nginxPreset) {
        fail("nginx_preset", "common.required");
      }
      if (
        !/^([A-Za-z0-9._-]*[A-Za-z0-9_-][A-Za-z0-9._-]*(\/[A-Za-z0-9._-]*[A-Za-z0-9_-][A-Za-z0-9._-]*)*)?$/.test(
          this.documentRoot.replace(/^\/+|\/+$/g, "")
        )
      ) {
        fail("document_root", "settings.document_root_invalid");
      }
      if (!this.phpVersion) {
        fail("php_version", "common.required");
      }
      const isCount = (value) => /^[1-9][0-9]*$/.test(value);
      for (const [field, value, low, high] of [
        ["php_memory_limit", this.phpMemoryLimitMib, 128, 4096],
        ["php_upload_max_filesize", this.phpUploadMaxFilesizeMib, 2, 2048],
      ]) {
        if (!isCount(value)) {
          fail(field, "settings.size_invalid");
        } else if (Number(value) < low || Number(value) > high) {
          fail(field, `settings.${field}_out_of_range`);
        }
      }
      if (
        isCount(this.phpMemoryLimitMib) &&
        isCount(this.phpUploadMaxFilesizeMib) &&
        Number(this.phpMemoryLimitMib) <= Number(this.phpUploadMaxFilesizeMib)
      ) {
        fail("php_memory_limit", "settings.php_memory_limit_too_low");
      }
      if (
        !this.isExecutionTimeUnlimited &&
        (!isCount(this.phpMaxExecutionTime) ||
          Number(this.phpMaxExecutionTime) > 3600)
      ) {
        fail(
          "php_max_execution_time",
          "settings.php_max_execution_time_invalid"
        );
      }
      if (!this.phpTimezone) {
        fail("php_timezone", "common.required");
      }
      if (
        !isCount(this.fpmPmMaxChildren) ||
        Number(this.fpmPmMaxChildren) > 100
      ) {
        fail("fpm_pm_max_children", "settings.fpm_pm_max_children_invalid");
      }
      if (!NAME_PATTERN.test(this.dbName) || this.dbName.length > 64) {
        fail("db_name", "settings.db_name_invalid");
      }
      if (
        !NAME_PATTERN.test(this.dbUser) ||
        this.dbUser.length > 32 ||
        RESERVED_USERS.includes(this.dbUser)
      ) {
        fail("db_user", "settings.db_user_invalid");
      }
      for (const [prefix, active, password, validation, focusField] of [
        [
          "db",
          this.isDbPasswordActive,
          this.dbPassword,
          this.dbPasswordValidation,
          "focusDbPasswordField",
        ],
        [
          "admin",
          this.isAdminPasswordActive,
          this.adminPassword,
          this.adminPasswordValidation,
          "focusAdminPasswordField",
        ],
      ]) {
        if (!active) {
          continue;
        }
        if (!password) {
          fail(
            `${prefix}_password`,
            `settings.${prefix}_password_required`,
            false
          );
          this[focusField] = { element: "newPassword" };
        } else if (!this.isStrongPassword(validation)) {
          fail(
            `${prefix}_password`,
            `settings.${prefix}_password_too_weak`,
            false
          );
          this[focusField] = { element: "newPassword" };
        } else if (!validation.isEqualOk) {
          fail(
            `${prefix}_password_confirm`,
            `settings.${prefix}_password_mismatch`,
            false
          );
          this[focusField] = { element: "confirmPassword" };
        }
      }
      if (this.isLdapEnabled && !this.userDomain) {
        fail("user_domain", "common.required");
      }
      return isValidationOk;
    },
    configureModuleValidationFailed(validationErrors) {
      this.loading.configureModule = false;
      let focusAlreadySet = false;
      for (const validationError of validationErrors) {
        const param = validationError.parameter;
        if (validationError.details) {
          this.validationErrorDetails = validationError.details
            .split("\n")
            .filter((detail) => detail.trim() !== "");
        } else {
          this.error[param] = this.$t("settings." + validationError.error);
          if (ADVANCED_FIELDS.includes(param)) {
            this.toggleAccordion = [true];
          }
          if (!focusAlreadySet) {
            if (param === "db_password") {
              this.focusDbPasswordField = { element: "newPassword" };
            } else if (param === "admin_password") {
              this.focusAdminPasswordField = { element: "newPassword" };
            } else {
              this.focusElement(param);
            }
            focusAlreadySet = true;
          }
        }
      }
    },
    async configureModule() {
      if (!this.validateConfigureModule()) {
        return;
      }

      this.loading.configureModule = true;
      const taskAction = "configure-module";
      const eventId = this.getUuid();
      this.core.$root.$once(
        `${taskAction}-aborted-${eventId}`,
        this.configureModuleAborted
      );
      this.core.$root.$once(
        `${taskAction}-validation-failed-${eventId}`,
        this.configureModuleValidationFailed
      );
      this.core.$root.$once(
        `${taskAction}-completed-${eventId}`,
        this.configureModuleCompleted
      );

      const data = {
        host: this.host,
        lets_encrypt: this.isLetsEncryptEnabled,
        nginx_preset: this.nginxPreset,
        document_root: this.documentRoot.replace(/^\/+|\/+$/g, ""),
        php_version: this.phpVersion,
        php_memory_limit: this.phpMemoryLimitMib + "M",
        php_upload_max_filesize: this.phpUploadMaxFilesizeMib + "M",
        php_max_execution_time: this.isExecutionTimeUnlimited
          ? 0
          : Number(this.phpMaxExecutionTime),
        php_timezone: this.phpTimezone,
        fpm_pm_max_children: Number(this.fpmPmMaxChildren),
        phpmyadmin_enabled: this.isPhpmyadminEnabled,
        db_name: this.dbName,
        db_user: this.dbUser,
        user_domain: this.isLdapEnabled ? this.userDomain : "",
        mail_from: this.mailFrom,
      };
      if (this.isDbPasswordActive) {
        data.db_password = this.dbPassword;
      }
      if (this.isAdminPasswordActive) {
        data.admin_password = this.adminPassword;
      }

      const res = await to(
        this.createModuleTaskForApp(this.instanceName, {
          action: taskAction,
          data,
          extra: {
            title: this.$t("settings.instance_configuration", {
              instance: this.instanceName,
            }),
            description: this.$t("settings.configuring"),
            eventId,
          },
        })
      );
      const err = res[0];
      if (err) {
        console.error(`error creating task ${taskAction}`, err);
        this.error.configureModule = this.getErrorMessage(err);
        this.loading.configureModule = false;
        return;
      }
    },
    configureModuleAborted(taskResult, taskContext) {
      console.error(`${taskContext.action} aborted`, taskResult);
      this.error.configureModule = this.$t("error.generic_error");
      this.loading.configureModule = false;
    },
    configureModuleCompleted() {
      this.loading.configureModule = false;
      this.getConfiguration();
    },
  },
};
</script>

<style scoped lang="scss">
@import "../styles/carbon-utils";
.mg-bottom {
  margin-bottom: $spacing-06;
}

.mg-bottom-md {
  margin-bottom: $spacing-05;
}

.mg-top {
  margin-top: $spacing-07;
}

.maxwidth {
  max-width: 38rem;
}
</style>

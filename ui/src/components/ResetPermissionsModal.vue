<!--
  Copyright (C) 2026 Nethesis S.r.l.
  SPDX-License-Identifier: GPL-3.0-or-later
-->
<template>
  <NsModal
    size="default"
    :visible="visible"
    :isLoading="loading.resetPermissions"
    @modal-hidden="onModalHidden"
    @primary-click="resetPermissions"
    kind="danger"
    :primary-button-disabled="loading.resetPermissions"
  >
    <template slot="title">
      {{ $t("settings.reset_permissions") }}
    </template>
    <template slot="content">
      <p>
        {{ $t("settings.reset_permissions_warning") }}
      </p>
      <div v-if="error.resetPermissions">
        <NsInlineNotification
          kind="error"
          :title="$t('action.reset-permissions')"
          :description="error.resetPermissions"
          :showCloseButton="false"
        />
      </div>
    </template>
    <template slot="secondary-button">{{ core.$t("common.cancel") }}</template>
    <template slot="primary-button">{{
      $t("settings.reset_permissions")
    }}</template>
  </NsModal>
</template>

<script>
import { UtilService, TaskService, IconService } from "@nethserver/ns8-ui-lib";
import to from "await-to-js";
import { mapState } from "vuex";

export default {
  name: "ResetPermissionsModal",
  mixins: [UtilService, TaskService, IconService],
  props: {
    visible: {
      type: Boolean,
      required: true,
    },
  },
  data() {
    return {
      error: { resetPermissions: "" },
      loading: { resetPermissions: false },
    };
  },
  computed: {
    ...mapState(["instanceName", "core"]),
  },
  methods: {
    async resetPermissions() {
      this.error.resetPermissions = "";
      this.loading.resetPermissions = true;
      const taskAction = "reset-permissions";
      const eventId = this.getUuid();

      this.core.$root.$once(
        `${taskAction}-aborted-${eventId}`,
        this.resetPermissionsAborted
      );
      this.core.$root.$once(
        `${taskAction}-completed-${eventId}`,
        this.resetPermissionsCompleted
      );

      const res = await to(
        this.createModuleTaskForApp(this.instanceName, {
          action: taskAction,
          data: {},
          extra: {
            title: this.$t("action.reset-permissions"),
            eventId,
          },
        })
      );
      const err = res[0];

      if (err) {
        console.error(`error creating task ${taskAction}`, err);
        this.error.resetPermissions = this.getErrorMessage(err);
        this.loading.resetPermissions = false;
      }
    },
    resetPermissionsAborted(taskResult, taskContext) {
      console.error(`${taskContext.action} aborted`, taskResult);
      this.error.resetPermissions = this.$t("error.generic_error");
      this.loading.resetPermissions = false;
    },
    resetPermissionsCompleted() {
      this.loading.resetPermissions = false;
      this.$emit("hide");
    },
    onModalHidden() {
      this.clearErrors();
      this.$emit("hide");
    },
  },
};
</script>

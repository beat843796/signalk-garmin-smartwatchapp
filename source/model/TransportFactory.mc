/*
 * TransportFactory.mc
 * Single point of construction for VesselConnect implementations.
 * Reads the user-picked connection type from Application.Storage and
 * returns the matching transport — REST, BLE, or the Null stand-in
 * when nothing has been picked yet.
 *
 * Centralised here so VesselModel / VesselConnectApp / the picker all
 * agree on how the (storage-key string) → (transport class) mapping
 * works. Storage values are strings (`"rest"` / `"ble"` / `"none"` /
 * absent) so they're self-documenting in the simulator's per-app .SET
 * file and in System.println logs.
 */

using Toybox.Lang;
using Toybox.Application.Storage;

module TransportFactory {

    /*
     * Reads the persisted connection-type. Treats "absent" the same as
     * "none" — first-launch users haven't picked yet, and the picker
     * is what populates the key.
     */
    function getStoredType() as Lang.String {
        var raw = Storage.getValue(StorageKeys.CONNECTION_TYPE);
        if (raw == null || !(raw instanceof Lang.String)) {
            return ConnectionType.NONE;
        }
        if (raw.equals(ConnectionType.REST) || raw.equals(ConnectionType.BLE)) {
            return raw;
        }
        return ConnectionType.NONE;
    }

    /*
     * Persists the user's pick. Values that round-trip through
     * getStoredType are the only ones written; "none" is stored as the
     * literal string (rather than deletion) so the storage key is
     * explicit and easy to spot in dumps.
     */
    function setStoredType(type as Lang.String) as Void {
        Storage.setValue(StorageKeys.CONNECTION_TYPE, type);
    }

    /*
     * Builds the transport that corresponds to `type` and binds it to
     * the supplied VesselModel. Caller is responsible for wiring the
     * returned transport into the model (vessel.attachTransport) and
     * for stopping the previous transport if any.
     */
    function build(type as Lang.String, vesselRef) as VesselConnect {
        if (type.equals(ConnectionType.REST)) {
            return new RESTVesselConnect(vesselRef);
        }
        if (type.equals(ConnectionType.BLE)) {
            return new BleVesselConnect(vesselRef);
        }
        return new NoneVesselConnect(vesselRef);
    }
}

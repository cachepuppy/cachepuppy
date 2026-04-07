let counter = 0;
export function nextId(prefix = "msg") {
    counter += 1;
    return `${prefix}_${Date.now()}_${counter}`;
}
export function createEnvelope(input) {
    return {
        v: 1,
        id: nextId(),
        ts: Date.now(),
        ...input,
    };
}
export function isEnvelope(value) {
    if (!value || typeof value !== "object") {
        return false;
    }
    const v = value;
    return v.v === 1 && typeof v.type === "string" && typeof v.id === "string";
}
